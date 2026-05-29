"""
Admin endpoints.

GET   /admin/users          — List all users (paginated)
PATCH /admin/users/{id}/role — Assign a role to a user
GET   /admin/stats          — System statistics
GET   /admin/agents/status  — Agent monitoring dashboard status
"""

from __future__ import annotations

import json
import math
import subprocess
import sys
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.dependencies import require_admin
from app.models.notification import Notification
from app.models.user import Role, User, UserRole
from app.schemas.admin import AgentStatusResponse
from app.schemas.auth import RoleRead, UserRead

router = APIRouter(prefix="/admin", tags=["admin"])


class UserWithRoles(UserRead):
    """User response with roles included."""

    roles: list[RoleRead] = []


class AdminStats(BaseModel):
    """System statistics response."""

    total_users: int = 0
    total_notifications: int = 0
    total_roles: int = 0


class RoleAssignRequest(BaseModel):
    """Request body for assigning a role to a user."""

    role_name: str


@router.get(
    "/users",
    response_model=dict,
    summary="List all users (admin)",
)
async def list_users(
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    admin_user: User = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Return a paginated list of all users with their roles.

    Requires admin privileges.
    """
    # Count total
    count_q = select(func.count()).select_from(User)
    total_result = await session.execute(count_q)
    total = total_result.scalar() or 0

    # Fetch page with roles
    offset = (page - 1) * page_size
    stmt = (
        select(User)
        .options(selectinload(User.roles).selectinload(UserRole.role))
        .order_by(User.created_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await session.execute(stmt)
    users = result.scalars().all()

    total_pages = max(1, math.ceil(total / page_size))

    users_data = []
    for user in users:
        user_dict = UserRead.model_validate(user).model_dump()
        user_dict["roles"] = [
            RoleRead.model_validate(ur.role).model_dump()
            for ur in user.roles
        ]
        users_data.append(user_dict)

    return {
        "items": users_data,
        "total": total,
        "page": page,
        "page_size": page_size,
        "total_pages": total_pages,
    }


@router.patch(
    "/users/{user_id}/role",
    response_model=UserRead,
    summary="Assign a role to a user (admin)",
)
async def assign_user_role(
    user_id: str,
    data: RoleAssignRequest,
    admin_user: User = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> UserRead:
    """Assign a role to a user by role name.

    Creates a UserRole association if one doesn't exist.
    Requires admin privileges.
    """
    # Find user
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )

    # Find role
    result = await session.execute(
        select(Role).where(Role.name == data.role_name)
    )
    role = result.scalar_one_or_none()
    if role is None:
        # Auto-create role if it doesn't exist
        role = Role(name=data.role_name)
        session.add(role)
        await session.flush()
        await session.refresh(role)

    # Check if user already has this role
    result = await session.execute(
        select(UserRole).where(
            UserRole.user_id == user.id,
            UserRole.role_id == role.id,
        )
    )
    existing = result.scalar_one_or_none()
    if existing is None:
        user_role = UserRole(user_id=user.id, role_id=role.id)
        session.add(user_role)
        await session.flush()

    await session.refresh(user)
    return UserRead.model_validate(user)


@router.get(
    "/stats",
    response_model=AdminStats,
    summary="System statistics (admin)",
)
async def get_stats(
    admin_user: User = Depends(require_admin),
    session: AsyncSession = Depends(get_session),
) -> AdminStats:
    """Return system-wide statistics.

    Requires admin privileges.
    """
    # Count users
    result = await session.execute(select(func.count()).select_from(User))
    total_users = result.scalar() or 0

    # Count notifications
    result = await session.execute(
        select(func.count()).select_from(Notification)
    )
    total_notifications = result.scalar() or 0

    # Count roles
    result = await session.execute(select(func.count()).select_from(Role))
    total_roles = result.scalar() or 0

    return AdminStats(
        total_users=total_users,
        total_notifications=total_notifications,
        total_roles=total_roles,
    )


# ── Paths for agent stats ──────────────────────────────────────────────

AGENT_STATS_JSON = Path.home() / "agent-control-room/bus/agent_stats.json"
COLLECTOR_SCRIPT = Path.home() / "workspace/super-app/scripts/collect_agent_stats.py"


@router.get(
    "/agents/status",
    response_model=AgentStatusResponse,
    summary="Agent monitoring dashboard status (admin)",
)
async def get_agents_status(
    admin_user: User = Depends(require_admin),
) -> AgentStatusResponse:
    """Return live status of all agents.

    Reads ``agent_stats.json`` if available.  If the file does not exist
    the collector script is executed on demand.

    Requires admin privileges.
    """
    if not AGENT_STATS_JSON.is_file():
        if not COLLECTOR_SCRIPT.is_file():
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Agent stats collector script not found",
            )
        try:
            subprocess.run(
                [sys.executable, str(COLLECTOR_SCRIPT)],
                capture_output=True,
                text=True,
                timeout=60,
                check=True,
            )
        except subprocess.TimeoutExpired:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail="Agent stats collector timed out",
            )
        except subprocess.CalledProcessError as exc:
            raise HTTPException(
                status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
                detail=f"Agent stats collector failed: {exc.stderr.strip()}",
            )

    if not AGENT_STATS_JSON.is_file():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Agent stats data unavailable",
        )

    try:
        with open(AGENT_STATS_JSON) as f:
            raw = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to read agent stats: {exc}",
        )

    return AgentStatusResponse(**raw)
