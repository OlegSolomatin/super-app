"""Telegram notification service.

Provides a helper to send messages via the Telegram Bot API.
"""

from __future__ import annotations

import httpx


async def send_telegram_notification(
    bot_token: str, chat_id: str, message: str
) -> bool:
    """Send a message via Telegram bot API.

    Args:
        bot_token: The Telegram bot token.
        chat_id: The target chat/group/user ID.
        message: The message text (HTML parse mode enabled).

    Returns:
        True if the message was sent successfully, False otherwise.
    """
    url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                url,
                json={
                    "chat_id": chat_id,
                    "text": message,
                    "parse_mode": "HTML",
                },
                timeout=10,
            )
            return resp.status_code == 200
        except Exception:
            return False
