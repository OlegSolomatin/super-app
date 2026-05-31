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
    TokenResponse,
    UserCreate,
)
from app.services.auth_service import AuthService

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
