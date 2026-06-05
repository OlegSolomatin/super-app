"""
Application configuration via Pydantic Settings.

Reads from .env file and environment variables.
"""

from __future__ import annotations

from typing import List

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Application settings loaded from environment variables."""

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # --- Database ---
    DATABASE_URL: str = "postgresql+asyncpg://postgres:postgres@localhost:5432/super_app"

    # --- JWT ---
    SECRET_KEY: str = "change-me-to-a-long-random-secret-key"
    JWT_ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 30
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7

    # --- Redis ---
    REDIS_URL: str = "redis://localhost:6379/0"

    # --- App ---
    APP_HOST: str = "0.0.0.0"
    APP_PORT: int = 8000
    CORS_ORIGINS: List[str] = ["http://localhost:3000", "http://localhost:8080"]
    DEBUG: bool = True

    # --- API Keys ---
    DEEPSEEK_API_KEY: str = ""


settings = Settings()
