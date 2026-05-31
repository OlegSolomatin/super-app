"""
Pydantic schemas for authentication and user management.

All schemas use Pydantic v2 syntax with from_attributes=True for ORM mode.
"""

from __future__ import annotations

from datetime import datetime
from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


# ─── Auth ────────────────────────────────────────────────────────────────────

class LoginRequest(BaseModel):
    """Login request payload."""

    username: str = Field(..., min_length=2, max_length=100)
    password: str = Field(..., min_length=6)


class Token(BaseModel):
    """Individual JWT token response."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


class TokenResponse(BaseModel):
    """Token response returned to client."""

    access_token: str
    refresh_token: str
    token_type: str = "bearer"


# ─── User ────────────────────────────────────────────────────────────────────

class UserCreate(BaseModel):
    """User registration payload."""

    model_config = ConfigDict(from_attributes=True)

    email: EmailStr
    password: str = Field(..., min_length=6, max_length=128)
    username: str = Field(..., min_length=2, max_length=100)


class UserUpdate(BaseModel):
    """User profile update payload."""

    model_config = ConfigDict(from_attributes=True)

    username: Optional[str] = Field(None, min_length=2, max_length=100)
    bio: Optional[str] = None
    avatar_url: Optional[str] = None


class UserRead(BaseModel):
    """User response model (public profile)."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    email: str
    username: str
    avatar_url: Optional[str] = None
    bio: Optional[str] = None
    roles: list[str] = []
    created_at: datetime
    updated_at: datetime


# ─── Role ────────────────────────────────────────────────────────────────────

class RoleCreate(BaseModel):
    """Role creation payload."""

    model_config = ConfigDict(from_attributes=True)

    name: str = Field(..., min_length=2, max_length=50)
    description: Optional[str] = None


class RoleRead(BaseModel):
    """Role response model."""

    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: Optional[str] = None
    created_at: datetime
