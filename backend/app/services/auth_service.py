"""
Authentication service for user registration, login, and token management.

Handles business logic for auth-related operations.
"""

from __future__ import annotations

from fastapi import Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    get_password_hash,
    verify_password,
)
from app.models.user import User
from app.schemas.auth import (
    LoginRequest,
    TokenResponse,
    UserCreate,
    UserRead,
)


class AuthService:
    """Service handling authentication and user management."""

    def __init__(self, session: AsyncSession = Depends(get_session)):
        self.session = session

    async def register(self, data: UserCreate) -> TokenResponse:
        """Register a new user and return JWT tokens.

        Args:
            data: User registration details (email, password, username).

        Returns:
            TokenResponse with access and refresh tokens.

        Raises:
            HTTPException: If email or username already exists.
        """
        # Check for existing email
        existing = await self.session.execute(
            select(User).where(User.email == data.email)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Email already registered",
            )

        # Check for existing username
        existing = await self.session.execute(
            select(User).where(User.username == data.username)
        )
        if existing.scalar_one_or_none():
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail="Username already taken",
            )

        # Create user
        user = User(
            email=data.email,
            username=data.username,
            password_hash=get_password_hash(data.password),
        )
        self.session.add(user)
        await self.session.flush()
        await self.session.refresh(user)

        # Generate tokens
        token_data = {"sub": str(user.id)}
        return TokenResponse(
            access_token=create_access_token(data=token_data),
            refresh_token=create_refresh_token(data=token_data),
        )

    async def login(self, data: LoginRequest) -> TokenResponse:
        """Authenticate a user and return JWT tokens.

        Args:
            data: Login credentials (email, password).

        Returns:
            TokenResponse with access and refresh tokens.

        Raises:
            HTTPException: If credentials are invalid.
        """
        result = await self.session.execute(
            select(User).where(User.email == data.email)
        )
        user = result.scalar_one_or_none()

        if user is None or not verify_password(data.password, user.password_hash):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid email or password",
            )

        token_data = {"sub": str(user.id)}
        return TokenResponse(
            access_token=create_access_token(data=token_data),
            refresh_token=create_refresh_token(data=token_data),
        )

    async def refresh_token(self, refresh_token: str) -> TokenResponse:
        """Issue new tokens using a valid refresh token.

        Args:
            refresh_token: A valid JWT refresh token.

        Returns:
            TokenResponse with new access and refresh tokens.
        """
        payload = decode_token(refresh_token)
        if payload is None or payload.get("type") != "refresh":
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid or expired refresh token",
            )

        user_id = payload.get("sub")
        if user_id is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Invalid refresh token payload",
            )

        # Verify user still exists
        result = await self.session.execute(
            select(User).where(User.id == user_id)
        )
        if result.scalar_one_or_none() is None:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="User not found",
            )

        return TokenResponse(
            access_token=create_access_token(subject=user_id),
            refresh_token=create_refresh_token(subject=user_id),
        )

    async def get_user_by_id(self, user_id: str) -> UserRead:
        """Get a user by their ID.

        Args:
            user_id: UUID string of the user.

        Returns:
            UserRead schema with user details.

        Raises:
            HTTPException: If user is not found.
        """
        result = await self.session.execute(
            select(User).where(User.id == user_id)
        )
        user = result.scalar_one_or_none()

        if user is None:
            raise HTTPException(
                status_code=status.HTTP_404_NOT_FOUND,
                detail="User not found",
            )

        return UserRead.model_validate(user)
