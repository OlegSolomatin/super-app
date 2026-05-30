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
import os
import subprocess
import sys
import urllib.request
import urllib.error
from pathlib import Path
from typing import Any

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


# ── DeepSeek Balance ──────────────────────────────────────────────────────────


DEEPSEEK_BALANCE_CACHE: dict[str, Any] = {"data": None, "updated": 0.0}


@router.get("/deepseek-balance")
async def get_deepseek_balance(
    admin_user: User = Depends(require_admin),
) -> dict[str, Any]:
    """Return current DeepSeek API account balance.

    Cached for 60 seconds to avoid hitting the API on every request.
    Requires admin privileges.
    """
    import time as _time

    now = _time.time()
    if DEEPSEEK_BALANCE_CACHE["data"] and now - DEEPSEEK_BALANCE_CACHE["updated"] < 60:
        return DEEPSEEK_BALANCE_CACHE["data"]

    api_key = os.environ.get("DEEPSEEK_API_KEY", "")
    if not api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="DEEPSEEK_API_KEY not configured",
        )

    try:
        req = urllib.request.Request(
            "https://api.deepseek.com/user/balance",
            headers={"Authorization": f"Bearer {api_key}"},
        )
        with urllib.request.urlopen(req, timeout=15) as resp:
            raw: dict[str, Any] = json.loads(resp.read().decode())
    except urllib.error.URLError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"DeepSeek API error: {exc.reason}",
        )
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=f"Failed to parse DeepSeek response: {exc}",
        )

    DEEPSEEK_BALANCE_CACHE["data"] = raw
    DEEPSEEK_BALANCE_CACHE["updated"] = now
    return raw


# ── Second Brain ──────────────────────────────────────────────────────────────

BRAIN_DIR = Path.home() / "brain"
BRAIN_GRAPH_JSON = BRAIN_DIR / "graph.json"
BRAIN_PARSER = BRAIN_DIR / ".parser" / "brain_parser.py"
REGENERATE_SCRIPT = BRAIN_DIR / ".parser" / "regenerate_graph.py"


class BrainNode(BaseModel):
    id: str
    title: str
    folder: str
    tags: list[str] = []
    status: str = ""
    date: str = ""
    lat: float | None = None
    lon: float | None = None
    address: str = ""
    time: str = ""
    weight: int = 1
    x: float = 0.0
    y: float = 0.0


class BrainEdge(BaseModel):
    source: str
    target: str
    weight: int = 1


class BrainGraphResponse(BaseModel):
    nodes: list[BrainNode]
    edges: list[BrainEdge]


class StatusChangeRequest(BaseModel):
    id: str
    status: str


@router.get(
    "/brain/graph",
    response_model=BrainGraphResponse,
    summary="Get brain knowledge graph (admin)",
)
async def get_brain_graph(
    admin_user: User = Depends(require_admin),
) -> BrainGraphResponse:
    """Return the brain knowledge graph from ~/brain/graph.json.

    Automatically regenerates if graph.json is stale or missing.
    Requires admin privileges.
    """
    _ensure_brain_parser()

    if not (BRAIN_DIR / "graph.json").is_file():
        _run_brain_parser()

    try:
        with open(BRAIN_GRAPH_JSON) as f:
            raw: dict[str, Any] = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Failed to read brain graph: {exc}",
        )

    nodes = raw.get("nodes", [])
    edges = raw.get("edges", [])

    # Compute circle positions if not present
    import math as _math
    n = len(nodes)
    for i, node in enumerate(nodes):
        if not node.get("x") or not node.get("y"):
            angle = 2 * _math.pi * i / max(n, 1)
            radius = max(200, n * 30)
            node["x"] = radius * _math.cos(angle) + 400
            node["y"] = radius * _math.sin(angle) + 300

    return BrainGraphResponse(
        nodes=[BrainNode(**n) for n in nodes],
        edges=[BrainEdge(**e) for e in edges],
    )


@router.post(
    "/brain/status",
    summary="Change note status (admin)",
)
async def set_brain_status(
    data: StatusChangeRequest,
    admin_user: User = Depends(require_admin),
) -> dict[str, Any]:
    """Change the status of a brain note.

    Finds the note by id, updates its YAML frontmatter status,
    and regenerates the graph.
    Requires admin privileges.
    """
    note_id: str = data.id
    new_status: str = data.status

    # Find the .md file by relative path stored in graph.json id
    md_path = BRAIN_DIR / f"{note_id}.md"
    if not md_path.is_file():
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Note not found: {note_id}",
        )

    try:
        content = md_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to read note: {exc}",
        )

    # Update status in YAML frontmatter
    lines = content.split("\n")
    if not content.startswith("---"):
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Note has no YAML frontmatter",
        )

    updated = False
    new_lines: list[str] = []
    in_frontmatter = False
    for line in lines:
        if line.strip() == "---":
            if not in_frontmatter:
                in_frontmatter = True
                new_lines.append(line)
                continue
            else:
                # End of frontmatter
                if not updated:
                    new_lines.append(f"status: {new_status}")
                    updated = True
                new_lines.append(line)
                in_frontmatter = False
                continue
        if in_frontmatter and line.strip().startswith("status:"):
            new_lines.append(f"status: {new_status}")
            updated = True
            continue
        new_lines.append(line)

    try:
        md_path.write_text("\n".join(new_lines), encoding="utf-8")
    except OSError as exc:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to write note: {exc}",
        )

    # Regenerate graph
    _run_brain_parser()

    return {"status": "ok", "id": note_id, "new_status": new_status}


def _ensure_brain_parser() -> None:
    """Ensure the brain parser scripts exist."""
    if not BRAIN_DIR.is_dir():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Brain directory not found: {BRAIN_DIR}",
        )


def _run_brain_parser() -> None:
    """Run the brain parser to regenerate graph.json."""
    if REGENERATE_SCRIPT.is_file():
        script = str(REGENERATE_SCRIPT)
    elif BRAIN_PARSER.is_file():
        script = str(BRAIN_PARSER)
    else:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Brain parser script not found",
        )

    try:
        subprocess.run(
            [sys.executable or "python3", script],
            capture_output=True,
            text=True,
            timeout=30,
            check=True,
            cwd=str(BRAIN_DIR),
        )
    except subprocess.TimeoutExpired:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Brain parser timed out",
        )
    except subprocess.CalledProcessError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=f"Brain parser failed: {exc.stderr.strip()[:500]}",
        )
