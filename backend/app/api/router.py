"""
Main API router aggregating all versioned sub-routers.
"""

from fastapi import APIRouter

from app.api.v1.admin import router as admin_router
from app.api.v1.auth import router as auth_router
from app.api.v1.notifications import router as notifications_router
from app.api.v1.users import router as users_router

api_router = APIRouter(prefix="/api/v1")

api_router.include_router(auth_router, tags=["auth"])
api_router.include_router(users_router, tags=["users"])
api_router.include_router(notifications_router, tags=["notifications"])
api_router.include_router(admin_router, tags=["admin"])
