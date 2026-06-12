"""Telegram notification bot for trading signals.

Listens to Redis pub/sub channels and sends notifications
via configured Telegram bots to specified chat IDs.

Channels listened:
  - channel:signal:new     — new raw signal from scraper
  - channel:signal:mapped  — signal classified by mapper
"""

from __future__ import annotations

import asyncio
import gc
import json
import logging
import os
import signal as signal_module
from typing import Optional

import httpx

logger = logging.getLogger("notification_bot")


class SignalNotifier:
    """Listens to Redis pub/sub and sends Telegram notifications."""

    def __init__(self, redis_url: str = "redis://localhost:6379/0"):
        self.redis_url = redis_url
        self._running = False
        self._bot_token: Optional[str] = None
        self._chat_id: Optional[str] = None
        self._http: Optional[httpx.AsyncClient] = None
        # Buffer: pair -> {raw_data, created_at}
        self._pending: dict[str, tuple[dict, float]] = {}
        self._pending_lock = asyncio.Lock()

    async def _flush_pending(self, pair: str, mapped: Optional[dict] = None):
        """Send a single combined notification for a pending signal.

        If mapped data is provided, merge raw + mapped into one message.
        If not (timeout), send raw signal with fallback text.
        """
        async with self._pending_lock:
            entry = self._pending.pop(pair, None)
            if entry is None:
                return

        raw = entry[0]

        if mapped:
            # Merge: raw fields + mapped fields → full message
            full = {**raw, **mapped}
            text = self._format_signal_combined(full)
        else:
            # Timeout: raw only
            text = self._format_signal_new(raw)

        await self._send_message(text)
        logger.info(
            "Sent %s notification for %s",
            "combined" if mapped else "raw-only",
            pair,
        )

    async def _load_bot_config(self) -> bool:
        """Load the first available Telegram bot config from DB."""
        try:
            from app.core.database import async_session_factory
            from app.models.telegram_bot import TelegramBot
            from sqlalchemy import select

            async with async_session_factory() as session:
                stmt = select(TelegramBot).limit(1)
                result = await session.execute(stmt)
                bot = result.scalar_one_or_none()

                if bot is None:
                    logger.warning("No Telegram bots configured in DB")
                    return False

                self._bot_token = bot.bot_token
                self._chat_id = bot.chat_id
                logger.info(
                    "Loaded bot '%s' (chat_id=%s)", bot.name, bot.chat_id
                )
                return True
        except Exception as e:
            logger.warning("Failed to load bot config: %s", e)
            return False

    async def _send_message(self, text: str, parse_mode: str = "HTML") -> bool:
        """Send a text message via the Telegram Bot API."""
        if not self._bot_token or not self._chat_id:
            return False

        # Lazily create shared httpx client (reused across all sends)
        if self._http is None:
            self._http = httpx.AsyncClient(
                timeout=httpx.Timeout(15.0, connect=10.0),
                limits=httpx.Limits(max_keepalive_connections=5, max_connections=10),
            )

        url = f"https://api.telegram.org/bot{self._bot_token}/sendMessage"
        payload = {
            "chat_id": self._chat_id,
            "text": text,
            "parse_mode": parse_mode,
            "disable_web_page_preview": True,
        }
        try:
            resp = await self._http.post(url, json=payload)
            if resp.status_code != 200:
                logger.warning(
                    "Telegram API error: %s %s",
                    resp.status_code,
                    resp.text,
                )
                return False
            return True
        except Exception as e:
            logger.warning("Telegram send failed: %s", e)
            return False

    def _format_signal_new(self, data: dict) -> str:
        """Format a new raw signal into a Telegram message (fallback when no mapping)."""
        pair = data.get("pair", "???")
        channel = data.get("channel", "?")
        exchange = data.get("exchange", "?")

        lines = [f"🔔 <b>{pair}</b> — {exchange}"]
        lines.append(f"📡 Канал: @{channel}")

        if data.get("price_range") is not None:
            lines.append(f"📊 Range: {data['price_range']}%")
        if data.get("vol_60m") is not None:
            lines.append(f"📈 Vol 60m: {self._format_vol(data['vol_60m'])}")
        if data.get("vol_10m") is not None:
            lines.append(f"📈 Vol 10m: {self._format_vol(data['vol_10m'])}")
        if data.get("slope") is not None:
            lines.append(f"📐 Slope: {data['slope']}")
        if data.get("top_ratio") is not None and data.get("bot_ratio") is not None:
            lines.append(
                f"🔵 Top: {data['top_ratio']} | 🔴 Bot: {data['bot_ratio']}"
            )

        lines.append("")
        lines.append("⏳ Нет классификации (таймаут)")

        return "\n".join(lines)

    def _format_signal_combined(self, data: dict) -> str:
        """Format a single combined message with raw + mapped signal data."""
        pair = data.get("pair", "???")
        channel = data.get("channel", "?")
        exchange = data.get("exchange", "?")
        signal_label = data.get("signal_label", "?")
        signal_type = data.get("signal_type", "?")
        mapped_strategy = data.get("mapped_strategy", "?")
        mapped_engine = data.get("mapped_engine", "?")
        params = data.get("mapped_params", {}) or {}
        available = data.get("available_exchanges") or {}
        confidence = data.get("confidence", 0)

        type_emoji = {
            "brush": "🧹",
            "stair": "🪜",
            "imbalance_top": "⬇️",
            "imbalance_bot": "⬆️",
            "volume_spike": "🌊",
        }.get(signal_type, "🔔")

        engine_label = "OrderBook" if mapped_engine == "ob" else "Trading"

        lines = [f"{type_emoji} <b>{pair}</b> — {exchange}"]
        lines.append(f"📡 @{channel} | 📊 {signal_label}")

        # Raw metrics
        metrics = []
        if data.get("price_range") is not None:
            metrics.append(f"Range: {data['price_range']}%")
        if data.get("vol_60m") is not None:
            metrics.append(f"Vol60m: {self._format_vol(data['vol_60m'])}")
        if data.get("vol_10m") is not None:
            metrics.append(f"Vol10m: {self._format_vol(data['vol_10m'])}")
        if data.get("slope") is not None:
            metrics.append(f"Slope: {data['slope']}")
        if data.get("top_ratio") is not None and data.get("bot_ratio") is not None:
            metrics.append(
                f"T/B: {data['top_ratio']}/{data['bot_ratio']}"
            )
        if metrics:
            lines.append("📊 " + " | ".join(metrics))

        # Available exchanges
        if available:
            avail_parts = []
            for exch, is_avail in sorted(available.items()):
                if is_avail:
                    avail_parts.append(f"<b>{exch.upper()}</b> ✅")
                else:
                    avail_parts.append(f"<b>{exch.upper()}</b> ❌")
            if avail_parts:
                lines.append("💱 " + ", ".join(avail_parts))

        if confidence:
            bars = "▓" * int(confidence * 10) + "░" * (
                10 - int(confidence * 10)
            )
            lines.append(f"🎯 {bars} {(confidence * 100):.0f}%")

        lines.append("")
        lines.append(f"⚙️ <b>{mapped_strategy}</b> ({engine_label})")

        # Key params
        param_parts = []
        if params.get("balance"):
            param_parts.append(f"💰 ${params['balance']}")
        if params.get("stoploss"):
            sl = abs(params["stoploss"])
            param_parts.append(f"🛑 SL: {sl:.1f}%")
        if params.get("takeprofit"):
            param_parts.append(f"✅ TP: {params['takeprofit']:.1f}%")
        if params.get("max_trade"):
            param_parts.append(f"📦 ${params['max_trade']}")
        if params.get("timeframe"):
            param_parts.append(f"⏱ {params['timeframe']}")
        if params.get("leverage"):
            param_parts.append(f"🔁 {params['leverage']}x")
        if params.get("max_hold"):
            hold_m = params["max_hold"] // 60
            param_parts.append(f"⏳ {hold_m}м")

        if param_parts:
            lines.append(" | ".join(param_parts))

        # Signal link
        signal_id = data.get("id")
        if signal_id:
            lines.append("")
            lines.append(
                f"🚀 <a href='https://pfumiko.ru/trading/signals/{signal_id}'>Открыть сигнал</a>"
            )

        return "\n".join(lines)

    def _format_signal_mapped(self, data: dict) -> str:
        """Format a classified signal into a Telegram message with actions."""
        pair = data.get("pair", "???")
        exchange = data.get("exchange", "?")
        signal_label = data.get("signal_label", "?")
        signal_type = data.get("signal_type", "?")
        mapped_strategy = data.get("mapped_strategy", "?")
        mapped_engine = data.get("mapped_engine", "?")
        params = data.get("mapped_params", {}) or {}
        fallback = data.get("fallback_exchange")
        available = data.get("available_exchanges") or {}
        confidence = data.get("confidence", 0)

        # Emoji by type
        type_emoji = {
            "brush": "🧹",
            "stair": "🪜",
            "imbalance_top": "⬇️",
            "imbalance_bot": "⬆️",
            "volume_spike": "🌊",
        }.get(signal_type, "🔔")

        engine_label = "OrderBook" if mapped_engine == "ob" else "Trading"

        lines = [f"{type_emoji} <b>{pair}</b> — {exchange}"]
        lines.append(f"📊 {signal_label}")

        # Show only exchanges where user has VALID API keys AND pair is available
        if available:
            avail_parts = []
            for exch, is_avail in sorted(available.items()):
                if is_avail:
                    avail_parts.append(f"<b>{exch.upper()}</b> ✅")
                else:
                    avail_parts.append(f"<b>{exch.upper()}</b> ❌")
            if avail_parts:
                lines.append("💱 " + ", ".join(avail_parts))

        if confidence:
            bars = "▓" * int(confidence * 10) + "░" * (
                10 - int(confidence * 10)
            )
            lines.append(f"🎯 {bars} {(confidence * 100):.0f}%")

        lines.append("")
        lines.append(f"⚙️ <b>{mapped_strategy}</b> ({engine_label})")

        # Format key params
        param_parts = []
        if params.get("balance"):
            param_parts.append(f"💰 ${params['balance']}")
        if params.get("stoploss"):
            sl = abs(params["stoploss"])
            param_parts.append(f"🛑 SL: {sl:.1f}%")
        if params.get("takeprofit"):
            param_parts.append(f"✅ TP: {params['takeprofit']:.1f}%")
        if params.get("max_trade"):
            param_parts.append(f"📦 ${params['max_trade']}")
        if params.get("timeframe"):
            param_parts.append(f"⏱ {params['timeframe']}")
        if params.get("leverage"):
            param_parts.append(f"🔁 {params['leverage']}x")
        if params.get("max_hold"):
            hold_m = params["max_hold"] // 60
            param_parts.append(f"⏳ {hold_m}м")

        if param_parts:
            lines.append(" | ".join(param_parts))

        # Signal ID for actions
        signal_id = data.get("id")
        if signal_id:
            lines.append("")
            lines.append(
                f"🚀 <a href='https://pfumiko.ru/trading/signals/{signal_id}'>Открыть сигнал</a>"
            )

        return "\n".join(lines)

    def _format_vol(self, vol: float) -> str:
        if vol >= 1_000_000:
            return f"${vol / 1_000_000:.1f}M"
        if vol >= 1_000:
            return f"${vol / 1_000:.1f}K"
        return f"${vol:.0f}"

    async def run_forever(self):
        """Main loop: listen to Redis pub/sub and send notifications."""
        logger.info("SignalNotifier starting...")

        if not await self._load_bot_config():
            logger.error("No bot configured — exiting")
            return

        # Reload bot config every hour (in case user adds new bot)
        _last_reload = asyncio.get_event_loop().time()
        _reload_interval = 3600  # 1 hour

        while self._running:
            from redis.asyncio import Redis

            r = Redis.from_url(
                self.redis_url,
                encoding="utf-8",
                decode_responses=True,
            )
            pubsub = r.pubsub()

            try:
                await pubsub.subscribe(
                    "channel:signal:new", "channel:signal:mapped"
                )
                logger.info(
                    "Subscribed to channel:signal:new and channel:signal:mapped"
                )

                while self._running:
                    try:
                        message = await pubsub.get_message(
                            timeout=1.0, ignore_subscribe_messages=True
                        )
                    except asyncio.TimeoutError:
                        # Normal — no message within 1s, keep polling
                        continue
                    except Exception as e:
                        logger.warning(
                            "get_message error: %s", e, exc_info=True
                        )
                        await asyncio.sleep(1)
                        continue

                    if message is None:
                        continue

                    channel = message["channel"]
                    try:
                        data = json.loads(message["data"])
                    except json.JSONDecodeError:
                        continue

                    # Periodic bot config reload + memory cleanup
                    now = asyncio.get_event_loop().time()
                    if now - _last_reload > _reload_interval:
                        await self._load_bot_config()
                        collected = gc.collect()
                        logger.info(
                            "Maintenance: bot config reloaded, gc collected %d objects",
                            collected,
                        )
                        _last_reload = now

                    if channel == "channel:signal:new":
                        pair = data.get("pair", "")
                        if not pair:
                            continue

                        # Buffer raw signal, start 5s timeout
                        now = asyncio.get_event_loop().time()
                        async with self._pending_lock:
                            self._pending[pair] = (data, now)

                        # Schedule flush on timeout (if no mapped arrives)
                        async def _timeout(p=pair):
                            await asyncio.sleep(5)
                            await self._flush_pending(p)

                        asyncio.create_task(_timeout())
                        logger.info("Buffered raw signal for %s (waiting for mapping)", pair)

                    elif channel == "channel:signal:mapped":
                        pair = data.get("pair", "")
                        if not pair:
                            continue

                        # Flush immediately with combined data
                        await self._flush_pending(pair, mapped=data)
                        logger.info(
                            "Mapped signal for %s → %s, sent combined notification",
                            pair,
                            data.get("mapped_strategy", "?"),
                        )

            except asyncio.CancelledError:
                break
            except Exception as e:
                logger.warning(
                    "Redis pub/sub error: %s — reconnecting in 5s",
                    e,
                    exc_info=True,
                )
                await asyncio.sleep(5)
            finally:
                await pubsub.unsubscribe()
                await r.aclose()

        logger.info("SignalNotifier stopped")


def run():
    """Convenience entry point: create notifier and run forever."""
    notifier = SignalNotifier()
    notifier._running = True

    # Handle graceful shutdown
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _stop():
        logger.info("Shutting down SignalNotifier...")
        notifier._running = False

    for sig in (signal_module.SIGINT, signal_module.SIGTERM):
        try:
            loop.add_signal_handler(sig, _stop)
        except (NotImplementedError, ValueError):
            pass  # Windows or test env

    try:
        loop.run_until_complete(notifier.run_forever())
    except KeyboardInterrupt:
        pass
    finally:
        loop.close()


if __name__ == "__main__":
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    run()
