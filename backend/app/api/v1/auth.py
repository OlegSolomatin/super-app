"""
Authentication endpoints.

POST /auth/register  — Register a new user
POST /auth/login     — Login with email/password
POST /auth/refresh   — Refresh access token
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from app.schemas.auth import (
    LoginRequest,
    PasswordChange,
    TokenResponse,
    UserCreate,
)
from app.services.auth_service import AuthService
from app.core.dependencies import get_current_user
from app.models.user import User

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post(
    "/register",
    response_model=TokenResponse,
    status_code=201,
    summary="Register a new user",
)
async def register(
    data: UserCreate,
    service: AuthService = Depends(),
) -> TokenResponse:
    """Register a new user account.

    Returns JWT access and refresh tokens upon successful registration.
    """
    return await service.register(data)


@router.post(
    "/login",
    response_model=TokenResponse,
    summary="Login with username and password",
)
async def login(
    data: LoginRequest,
    service: AuthService = Depends(),
) -> TokenResponse:
    """Authenticate a user with username and password.

    Returns JWT access and refresh tokens upon successful authentication.
    """
    return await service.login(data)


@router.post(
    "/refresh",
    response_model=TokenResponse,
    summary="Refresh access token",
)
async def refresh(
    refresh_token: str,
    service: AuthService = Depends(),
) -> TokenResponse:
    """Issue new tokens using a valid refresh token."""
    return await service.refresh_token(refresh_token)


@router.post(
    "/change-password",
    summary="Change current user password",
)
async def change_password(
    data: PasswordChange,
    current_user: User = Depends(get_current_user),
    service: AuthService = Depends(),
) -> dict:
    """Change the password for the currently authenticated user.

    Requires the current password for verification.
    """
    return await service.change_password(data, current_user)
