"""Check exchange keys for upcoming expiration and send Telegram notifications.

Runs daily via cron. Sends notifications 5 days before expiration.

Usage:
    python3 scripts/check_key_expiry.py

Environment:
    Must be run with PYTHONPATH pointing to backend root.
    Requires working DB connection and at least one Telegram bot in DB.
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
from datetime import datetime, timedelta, timezone

# Ensure backend is importable
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

import httpx
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

from app.core.config import settings
from app.models.exchange_key import ExchangeKey
from app.models.telegram_bot import TelegramBot

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("key_expiry")


async def main() -> None:
    """Check all exchange keys and send expiry notifications."""
    engine = create_async_engine(settings.DATABASE_URL)

    async with AsyncSession(engine) as session:
        # 1. Find keys expiring within 5 days
        now = datetime.now(timezone.utc)
        alert_threshold = now + timedelta(days=5)

        stmt = select(ExchangeKey).where(
            ExchangeKey.expires_at.isnot(None),
            ExchangeKey.is_active == True,
        )
        result = await session.execute(stmt)
        keys = result.scalars().all()

        if not keys:
            logger.info("No keys with expiration set")
            return

        # Get the first Telegram bot for sending
        bot_stmt = select(TelegramBot).limit(1)
        bot_result = await session.execute(bot_stmt)
        bot = bot_result.scalar_one_or_none()

        if not bot:
            logger.warning("No Telegram bot found in DB, cannot send notifications")
            return

        bot_token = _decrypt_bot_token(bot)
        if not bot_token:
            logger.warning("Bot token is empty or encrypted, cannot send")
            return

        for key in keys:
            if key.expires_at is None:
                continue

            remaining = key.expires_at - now
            days_left = remaining.days
            hours_left = remaining.total_seconds() / 3600

            # Skip if more than 5 days left
            if days_left > 5:
                continue

            # Build message
            if days_left < 0:
                # Already expired
                msg = (
                    f"⚠️ <b>Ключ биржи истёк!</b>\n\n"
                    f"🔑 {key.label or key.exchange.upper()}\n"
                    f"🏛 {key.exchange.upper()}\n"
                    f"📅 Истёк {key.expires_at.strftime('%d.%m.%Y %H:%M')} МСК\n\n"
                    f"Обновите ключ в настройках."
                )
            elif days_left == 0:
                msg = (
                    f"⚠️ <b>Ключ биржи истекает сегодня!</b>\n\n"
                    f"🔑 {key.label or key.exchange.upper()}\n"
                    f"🏛 {key.exchange.upper()}\n"
                    f"📅 Истекает через {int(hours_left)} часов\n\n"
                    f"Обновите ключ в настройках."
                )
            elif days_left <= 5:
                msg = (
                    f"⏰ <b>Ключ биржи скоро истечёт</b>\n\n"
                    f"🔑 {key.label or key.exchange.upper()}\n"
                    f"🏛 {key.exchange.upper()}\n"
                    f"📅 Осталось {days_left} дн.\n"
                    f"🗓 Истекает: {key.expires_at.strftime('%d.%m.%Y %H:%M')} МСК\n\n"
                    f"Обновите ключ в настройках."
                )
            else:
                continue

            # Send notification
            async with httpx.AsyncClient() as client:
                try:
                    resp = await client.post(
                        f"https://api.telegram.org/bot{bot_token}/sendMessage",
                        json={
                            "chat_id": bot.chat_id,
                            "text": msg,
                            "parse_mode": "HTML",
                        },
                        timeout=10,
                    )
                    if resp.status_code == 200:
                        logger.info(
                            "Sent expiry notification for %s (%s), %d days left",
                            key.exchange, key.label, days_left,
                        )
                    else:
                        logger.warning(
                            "Failed to send notification for %s: HTTP %d %s",
                            key.exchange, resp.status_code, resp.text[:200],
                        )
                except Exception as e:
                    logger.error("Failed to send notification: %s", e)

    await engine.dispose()


def _decrypt_bot_token(bot: TelegramBot) -> str | None:
    """Try to decrypt bot token if encrypted, or return as-is."""
    token: str | None = bot.bot_token  # type: ignore[assignment]
    if not token:
        return None

    # Try to decrypt (Fernet encrypted tokens)
    try:
        from app.core.encryption import decrypt_api_key
        decrypted = decrypt_api_key(token)  # type: ignore[arg-type]
        if decrypted:
            return decrypted
    except Exception:
        pass

    # Return as-is (plain text token)
    return token


if __name__ == "__main__":
    asyncio.run(main())
