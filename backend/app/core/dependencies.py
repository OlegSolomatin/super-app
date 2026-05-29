"""
Dependency injection for FastAPI.

Provides reusable dependencies like current user retrieval and admin checks.
"""

from __future__ import annotations

from typing import Optional

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.security import decode_token
from app.models.user import Role, User, UserRole

security_scheme = HTTPBearer()


async def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(security_scheme),
    session: AsyncSession = Depends(get_session),
) -> User:
    """Dependency that extracts and validates the current user from JWT."""
    token = credentials.credentials
    payload = decode_token(token)

    if payload is None or payload.get("type") != "access":
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or expired access token",
            headers={"WWW-Authenticate": "Bearer"},
        )

    user_id: Optional[str] = payload.get("sub")
    if user_id is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid token payload",
            headers={"WWW-Authenticate": "Bearer"},
        )

    result = await session.execute(select(User).where(User.id == user_id))
    user = result.scalar_one_or_none()

    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="User not found",
            headers={"WWW-Authenticate": "Bearer"},
        )

    return user


async def get_optional_user(
    credentials: Optional[HTTPAuthorizationCredentials] = Depends(HTTPBearer(auto_error=False)),
    session: AsyncSession = Depends(get_session),
) -> Optional[User]:
    """Dependency that returns the current user or None if not authenticated."""
    if credentials is None:
        return None

    payload = decode_token(credentials.credentials)
    if payload is None or payload.get("type") != "access":
        return None

    user_id: Optional[str] = payload.get("sub")
    if user_id is None:
        return None

    result = await session.execute(select(User).where(User.id == user_id))
    return result.scalar_one_or_none()


async def require_admin(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> User:
    """Dependency that verifies the current user has the 'admin' role.

    Raises:
        HTTPException 403: If user does not have the admin role.
    """
    stmt = (
        select(UserRole)
        .options(selectinload(UserRole.role))
        .where(
            UserRole.user_id == current_user.id,
        )
    )
    result = await session.execute(stmt)
    user_roles = result.scalars().all()

    for ur in user_roles:
        if ur.role.name == "admin":
            return current_user

    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Admin privileges required",
    )
