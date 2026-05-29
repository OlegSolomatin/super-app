"""
FastAPI application entry point.

Initializes the app with lifespan, CORS middleware, and API routers.
"""

from __future__ import annotations

from contextlib import asynccontextmanager
from typing import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.router import api_router
from app.core.config import settings


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    """Application lifespan: startup and shutdown events."""
    # Startup
    from app.core.database import engine
    # Engine is already created at import time; we just log readiness
    print(f"🚀 Super-App backend starting on {settings.APP_HOST}:{settings.APP_PORT}")
    yield
    # Shutdown
    await engine.dispose()
    print("🛑 Super-App backend shut down")


app = FastAPI(
    title="Super-App API",
    description="Backend API for Super-App — social, fitness, music, video, and tracking.",
    version="0.1.0",
    lifespan=lifespan,
    docs_url="/docs",
    redoc_url="/redoc",
)

# CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Include API routers
app.include_router(api_router)


@app.get("/", tags=["health"])
async def root() -> dict:
    """Health check endpoint."""
    return {
        "status": "ok",
        "service": "super-app-backend",
        "version": "0.1.0",
    }


@app.get("/health", tags=["health"])
async def health() -> dict:
    """Detailed health check endpoint."""
    return {
        "status": "healthy",
        "database": "check via /health/db in future versions",
    }
