"""
User management endpoints.

GET   /users/me  — Get current user profile
PATCH /users/me  — Update current user profile
GET   /users/{id} — Get user by ID
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.notification import Notification
from app.models.user import Role, User, UserRole
from app.schemas.auth import RoleRead, UserRead, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "/me",
    response_model=UserRead,
    summary="Get current user profile",
)
async def get_me(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UserRead:
    """Return the profile of the currently authenticated user."""
    # Build user dict without roles (SQLAlchemy relationship can't auto-extract)
    user_data = UserRead(
        id=current_user.id,
        email=current_user.email,
        username=current_user.username,
        avatar_url=current_user.avatar_url,
        bio=current_user.bio,
        created_at=current_user.created_at,
        updated_at=current_user.updated_at,
    )
    # Load roles from the many-to-many relationship
    stmt = (
        select(UserRole)
        .options(selectinload(UserRole.role))
        .where(UserRole.user_id == current_user.id)
    )
    result = await session.execute(stmt)
    user_roles = result.scalars().all()
    user_data.roles = [ur.role.name for ur in user_roles]
    return user_data


@router.patch(
    "/me",
    response_model=UserRead,
    summary="Update current user profile",
)
async def update_me(
    data: UserUpdate,
    current_user: User = Depends(get_current_user),
) -> UserRead:
    """Update the profile of the currently authenticated user.

    Only provided fields are updated (username, bio, avatar_url).
    """
    update_data = data.model_dump(exclude_unset=True)
    for field, value in update_data.items():
        setattr(current_user, field, value)
    # current_user is already tracked by the session, changes are auto-flushed
    return UserRead.model_validate(current_user)


@router.get(
    "/{user_id}",
    response_model=UserRead,
    summary="Get user by ID",
)
async def get_user(
    user_id: str,
    session: AsyncSession = Depends(get_session),
) -> UserRead:
    """Return a user's public profile by their UUID."""
    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="User not found",
        )
    return UserRead.model_validate(user)
