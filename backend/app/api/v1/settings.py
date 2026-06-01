"""API router for user settings (Telegram bots, preferences, etc.)."""

from __future__ import annotations

from typing import List
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.telegram_bot import TelegramBot
from app.models.user import User
from app.schemas.telegram_bot import TelegramBotCreate, TelegramBotResponse

router = APIRouter(prefix="/settings", tags=["settings"])


@router.get("/telegram-bots", response_model=List[TelegramBotResponse])
async def list_telegram_bots(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> List[TelegramBot]:
    """List all Telegram bots configured by the current user."""
    result = await session.execute(
        select(TelegramBot).where(TelegramBot.user_id == current_user.id)
    )
    return list(result.scalars().all())


@router.post("/telegram-bots", response_model=TelegramBotResponse, status_code=status.HTTP_201_CREATED)
async def create_telegram_bot(
    data: TelegramBotCreate,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TelegramBot:
    """Create a new Telegram bot notification configuration."""
    bot = TelegramBot(
        user_id=current_user.id,
        name=data.name,
        bot_token=data.bot_token,
        chat_id=data.chat_id,
    )
    session.add(bot)
    await session.flush()
    await session.refresh(bot)
    return bot


@router.delete("/telegram-bots/{bot_id}")
async def delete_telegram_bot(
    bot_id: UUID,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Delete a Telegram bot configuration (only own bots)."""
    result = await session.execute(
        select(TelegramBot).where(
            TelegramBot.id == bot_id,
            TelegramBot.user_id == current_user.id,
        )
    )
    bot = result.scalar_one_or_none()
    if bot is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Telegram bot not found",
        )
    await session.delete(bot)
    return {"message": f"Telegram bot '{bot.name}' deleted successfully"}
