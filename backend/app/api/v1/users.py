"""
User management endpoints.

GET  /users/me  — Get current user profile
GET  /users/{id} — Get user by ID
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.core.dependencies import get_current_user
from app.models.user import User
from app.schemas.auth import UserRead
from app.services.auth_service import AuthService

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


@router.get(
    "/{user_id}",
    response_model=UserRead,
    summary="Get user by ID",
)
async def get_user(
    user_id: str,
    service: AuthService = Depends(),
) -> UserRead:
    """Return a user's public profile by their UUID."""
    return await service.get_user_by_id(user_id)
