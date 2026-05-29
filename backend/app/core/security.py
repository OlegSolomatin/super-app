"""Security utilities: JWT tokens and password hashing.

Uses python-jose for JWT and bcrypt directly for passwords.
"""

from __future__ import annotations

import bcrypt
from datetime import datetime, timedelta, timezone
from typing import Any, Optional

from jose import JWTError, jwt

from app.core.config import settings


def get_password_hash(password: str) -> str:
    """Hash a plaintext password using bcrypt."""
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(plain_password: str, hashed_password: str) -> bool:
    """Verify a plaintext password against a bcrypt hash."""
    return bcrypt.checkpw(
        plain_password.encode("utf-8"), hashed_password.encode("utf-8")
    )


def create_access_token(
    subject: str | Any,
    data: Optional[dict] = None,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Create a JWT access token with short expiration.

    Args:
        subject: User identifier (sub claim).
        data: Optional additional claims.
        expires_delta: Custom expiration time.
    """
    to_encode = {"sub": str(subject)}
    if data:
        to_encode.update(data)
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
    )
    to_encode.update({"exp": expire, "type": "access"})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def create_refresh_token(
    subject: str | Any,
    data: Optional[dict] = None,
    expires_delta: Optional[timedelta] = None,
) -> str:
    """Create a JWT refresh token with long expiration.

    Args:
        subject: User identifier (sub claim).
        data: Optional additional claims.
        expires_delta: Custom expiration time.
    """
    to_encode = {"sub": str(subject)}
    if data:
        to_encode.update(data)
    expire = datetime.now(timezone.utc) + (
        expires_delta or timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS)
    )
    to_encode.update({"exp": expire, "type": "refresh"})
    return jwt.encode(to_encode, settings.SECRET_KEY, algorithm=settings.JWT_ALGORITHM)


def decode_token(token: str) -> Optional[dict]:
    """Decode and validate a JWT token. Returns payload or None."""
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.JWT_ALGORITHM]
        )
        return payload
    except JWTError:
        return None
