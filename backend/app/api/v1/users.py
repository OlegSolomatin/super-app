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

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.auth import UserRead, UserUpdate

router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "/me",
    response_model=UserRead,
    summary="Get current user profile",
)
async def get_me(
    current_user: User = Depends(get_current_user),
) -> UserRead:
    """Return the profile of the currently authenticated user."""
    return UserRead.model_validate(current_user)


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
