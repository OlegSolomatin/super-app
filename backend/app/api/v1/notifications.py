"""
Notification endpoints.

GET    /notifications              — List notifications (paginated)
PATCH  /notifications/{id}/read    — Mark one notification as read
PATCH  /notifications/read-all     — Mark all notifications as read
GET    /notifications/unread-count — Count of unread notifications
"""

from __future__ import annotations

import math

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import func, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.notification import Notification
from app.models.user import User
from app.schemas.notification import (
    NotificationPaginated,
    NotificationRead,
    UnreadCountResponse,
)

router = APIRouter(prefix="/notifications", tags=["notifications"])


@router.get(
    "",
    response_model=NotificationPaginated,
    summary="List user notifications",
)
async def list_notifications(
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=100, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationPaginated:
    """Return a paginated list of notifications for the current user.

    Ordered by created_at descending (newest first).
    """
    # Count total
    count_q = select(func.count()).where(
        Notification.user_id == current_user.id
    )
    total_result = await session.execute(count_q)
    total = total_result.scalar() or 0

    # Fetch page
    offset = (page - 1) * page_size
    stmt = (
        select(Notification)
        .where(Notification.user_id == current_user.id)
        .order_by(Notification.created_at.desc())
        .offset(offset)
        .limit(page_size)
    )
    result = await session.execute(stmt)
    notifications = result.scalars().all()

    total_pages = max(1, math.ceil(total / page_size))

    return NotificationPaginated(
        items=[NotificationRead.model_validate(n) for n in notifications],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.patch(
    "/{notification_id}/read",
    response_model=NotificationRead,
    summary="Mark notification as read",
)
async def mark_notification_read(
    notification_id: str,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> NotificationRead:
    """Mark a single notification as read by its ID.

    Only the owner of the notification can mark it as read.
    """
    stmt = select(Notification).where(
        Notification.id == notification_id,
        Notification.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    notification = result.scalar_one_or_none()

    if notification is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Notification not found",
        )

    if not notification.is_read:
        notification.is_read = True
        await session.flush()
        await session.refresh(notification)

    return NotificationRead.model_validate(notification)


@router.patch(
    "/read-all",
    summary="Mark all notifications as read",
)
async def mark_all_notifications_read(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Mark every unread notification for the current user as read."""
    stmt = (
        update(Notification)
        .where(
            Notification.user_id == current_user.id,
            Notification.is_read == False,  # noqa: E712
        )
        .values(is_read=True)
    )
    result = await session.execute(stmt)
    updated_count = result.rowcount

    return {"status": "ok", "updated_count": updated_count}


@router.get(
    "/unread-count",
    response_model=UnreadCountResponse,
    summary="Count unread notifications",
)
async def unread_notification_count(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> UnreadCountResponse:
    """Return the number of unread notifications for the current user."""
    stmt = select(func.count()).where(
        Notification.user_id == current_user.id,
        Notification.is_read == False,  # noqa: E712
    )
    result = await session.execute(stmt)
    unread_count = result.scalar() or 0

    return UnreadCountResponse(unread_count=unread_count)
