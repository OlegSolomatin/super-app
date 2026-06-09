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
    # Cleanup orphaned OB engines from previous runs
    try:
        from app.services.trading.scheduler import scheduler
        await scheduler.startup()
        # startup() already logs what it did
    except Exception as e:
        print(f"⚠️  Orphaned engine cleanup failed: {e}")

    # Cleanup orphaned regular trading runs
    try:
        from datetime import datetime, timezone
        from sqlalchemy import select
        from app.core.database import async_session_factory
        from app.models.trading import TradingRun as DBTradingRun
        async with async_session_factory() as session:
            stmt = select(DBTradingRun).where(DBTradingRun.status == "running")
            result = await session.execute(stmt)
            orphaned_runs = result.scalars().all()
            for run in orphaned_runs:
                run.status = "error"
                run.error = "Cleanup: engine lost on server restart"
                run.finished_at = datetime.now(timezone.utc)
            await session.commit()
            if orphaned_runs:
                print(f"🧹 Cleaned {len(orphaned_runs)} orphaned regular runs: {[r.id for r in orphaned_runs]}")
    except Exception as e:
        print(f"⚠️  Regular run cleanup failed: {e}")

    yield
    # Shutdown
    await engine.dispose()
    from app.core.cache import close_redis
    await close_redis()
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
