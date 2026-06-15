"""Telegram notification bot for trading signals — instant delivery.

Listens to Redis pub/sub channels and sends notifications
via configured Telegram bots to specified chat IDs.

Channels listened:
  - channel:signal:new      — new raw signal → sent IMMEDIATELY
  - channel:signal:mapped   — classified signal → sent as SEPARATE message
"""

from __future__ import annotations

import asyncio
import gc
import json
import logging
import os
import signal as signal_module
import time
from typing import Optional

import httpx

logger = logging.getLogger("notification_bot")


class SignalNotifier:
    """Listens to Redis pub/sub and sends Telegram notifications with buffered ordering."""

    def __init__(self, redis_url: str = "redis://localhost:6379/0"):
        self.redis_url = redis_url
        self._running = True
        self._bot_token: Optional[str] = None
        self._chat_id: Optional[str] = None
        self._http = httpx.AsyncClient(timeout=10)
        self._last_reload = 0.0
        self._reload_interval = 3600  # Reload bot config every hour
        # Buffer for ordered delivery
        self._buffer: dict[int, dict] = {}  # signal_id → data
        self._flush_task: Optional[asyncio.Task] = None
        self._flush_delay = 3.0  # seconds to wait for batching

    async def _load_bot_config(self) -> bool:
        """Load the first active Telegram bot from DB."""
        try:
            from app.core.database import async_session_factory
            from app.models.telegram_bot import TelegramBot
            from sqlalchemy import select

            async with async_session_factory() as session:
                stmt = select(TelegramBot).limit(1)
                result = await session.execute(stmt)
                bot = result.scalar_one_or_none()

                if bot:
                    self._bot_token = bot.bot_token
                    self._chat_id = bot.chat_id
                    logger.info("Loaded bot config: token=***%s, chat_id=%s",
                                bot.bot_token[-8:] if len(bot.bot_token) > 8 else "",
                                bot.chat_id)
                    return True
                else:
                    logger.warning("No active Telegram bot found in DB")
                    return False
        except Exception as e:
            logger.error("Failed to load bot config: %s", e)
            return False

    async def send_telegram(self, text: str, reply_markup: Optional[dict] = None) -> bool:
        """Send a message via the configured Telegram bot."""
        if not self._bot_token or not self._chat_id:
            logger.warning("No bot configured, skipping notification")
            return False

        url = f"https://api.telegram.org/bot{self._bot_token}/sendMessage"
        payload = {
            "chat_id": self._chat_id,
            "text": text,
            "parse_mode": "HTML",
            "disable_web_page_preview": True,
        }
        if reply_markup:
            payload["reply_markup"] = reply_markup
        try:
            resp = await self._http.post(url, json=payload)
            if resp.status_code != 200:
                logger.warning("Telegram API error: %s — %s", resp.status_code, resp.text[:200])
                return False
            return True
        except Exception as e:
            logger.warning("Telegram send failed: %s", e)
            return False

    def _format_raw_signal(self, data: dict) -> str:
        """Format a raw signal for immediate notification (no classification yet)."""
        pair = data.get("pair", "???")
        channel = data.get("channel", "?")
        exchange = data.get("exchange", "?")

        type_emoji = "🧹" if channel == "brushscreener" else "🪜"

        lines = [f"{type_emoji} <b>{pair}</b> — {exchange}"]
        lines.append(f"📡 @{channel}")

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
            metrics.append(f"T/B: {data['top_ratio']}/{data['bot_ratio']}")
        if metrics:
            lines.append("📊 " + " | ".join(metrics))

        lines.append("")
        lines.append("⏳ Классификация...")

        return "\n".join(lines)

    def _format_mapped_signal(self, data: dict) -> str:
        """Format a classified signal into a Telegram message."""
        pair = data.get("pair", "???")
        exchange = data.get("exchange", "?")
        signal_label = data.get("signal_label", "?")
        signal_type = data.get("signal_type", "?")
        mapped_strategy = data.get("mapped_strategy", "?")
        mapped_engine = data.get("mapped_engine", "?")
        params = data.get("mapped_params", {}) or {}
        available = data.get("available_exchanges") or {}
        confidence = data.get("confidence", 0)
        direction = data.get("direction", "long")
        current_price = data.get("current_price")

        type_emoji = {
            "brush": "🧹",
            "stair": "🪜",
            "imbalance_top": "⬇️",
            "imbalance_bot": "⬆️",
            "volume_spike": "🌊",
        }.get(signal_type, "🔔")

        # Direction
        dir_emoji = "🟢" if direction == "long" else "🔴"
        dir_label = "Long" if direction == "long" else "Short"

        engine_label = "OrderBook" if mapped_engine == "ob" else "Trading"

        lines = [f"{type_emoji} <b>{pair}</b> — {exchange}"]
        lines.append(f"{dir_emoji} <b>{dir_label}</b> | {signal_label}")

        # Current price
        if current_price is not None:
            lines.append(f"💵 ${current_price:.8f}" if current_price < 1 else f"💵 ${current_price:.4f}")

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
            bars = "▓" * int(confidence * 10) + "░" * (10 - int(confidence * 10))
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

        return "\n".join(lines)

    def _format_vol(self, vol: float) -> str:
        if vol >= 1_000_000:
            return f"${vol / 1_000_000:.1f}M"
        if vol >= 1_000:
            return f"${vol / 1_000:.1f}K"
        return f"${vol:.0f}"

    async def _add_to_buffer(self, data: dict):
        """Add a mapped signal to buffer and schedule flush."""
        signal_id = data.get("id")
        if not signal_id:
            return

        self._buffer[signal_id] = data

        # Cancel previous flush timer
        if self._flush_task and not self._flush_task.done():
            self._flush_task.cancel()

        # Schedule new flush after delay
        self._flush_task = asyncio.create_task(self._delayed_flush())

    async def _delayed_flush(self):
        """Wait for buffer delay, then send all buffered signals in order."""
        try:
            await asyncio.sleep(self._flush_delay)
        except asyncio.CancelledError:
            return  # A new signal arrived, timer was reset

        if not self._buffer:
            return

        # Sort by signal ID ascending
        sorted_ids = sorted(self._buffer.keys())
        batch = [self._buffer[sid] for sid in sorted_ids]
        self._buffer.clear()

        logger.info("Flushing %d buffered signals (IDs: %s)", len(batch), sorted_ids)

        for data in batch:
            try:
                text = self._format_mapped_signal(data)
                inline_kb = self._build_inline_keyboard(data)
                sent = await self.send_telegram(text, reply_markup=inline_kb)
                if sent:
                    logger.info(
                        "Sent mapped signal #%d (%s)",
                        data.get("id"), data.get("pair"),
                    )
            except Exception as e:
                logger.error("Failed to send buffered signal #%d: %s", data.get("id"), e)

    def _build_inline_keyboard(self, data: dict) -> Optional[dict]:
        """Build inline keyboard for a mapped signal."""
        signal_id = data.get("id")
        available = data.get("available_exchanges") or {}

        # Find first available exchange
        launch_exch = None
        for exch, is_avail in sorted(available.items()):
            if is_avail:
                launch_exch = exch.upper()
                break

        buttons = []
        if signal_id:
            buttons.append({
                "text": "🔍 Открыть на сайте",
                "url": f"https://pfumiko.ru/trading/signals/{signal_id}",
            })
        if launch_exch:
            buttons.append({
                "text": f"🚀 Запустить на {launch_exch}",
                "url": f"https://pfumiko.ru/trading/signals/{signal_id}?mode=real&exchange={launch_exch.lower()}",
            })

        if not buttons:
            return None

        kb = {"inline_keyboard": [buttons] if len(buttons) <= 2 else [buttons]}
        return kb

    async def run_forever(self):
        """Main loop: listen to Redis pub/sub, buffer mapped signals, send in order."""
        logger.info("SignalNotifier starting (buffered delivery, %ss window)...", self._flush_delay)

        if not await self._load_bot_config():
            logger.error("No bot configured - exiting")
            return

        # Heartbeat: refresh Redis lock every 10s
        LOCK_KEY = "service:lock:notification_bot"

        async def _heartbeat():
            while self._running:
                try:
                    r = Redis.from_url(self.redis_url, encoding="utf-8", decode_responses=True)
                    r.expire(LOCK_KEY, 30)
                    await r.aclose()
                except Exception:
                    pass
                await asyncio.sleep(10)

        hb_task = asyncio.create_task(_heartbeat())

        while self._running:
            from redis.asyncio import Redis

            r = Redis.from_url(
                self.redis_url,
                encoding="utf-8",
                decode_responses=True,
            )
            pubsub = r.pubsub()

            try:
                await pubsub.subscribe("channel:signal:mapped")
                logger.info("Subscribed to channel:signal:mapped (buffered)")

                while self._running:
                    try:
                        message = await pubsub.get_message(
                            timeout=1.0, ignore_subscribe_messages=True
                        )
                    except asyncio.TimeoutError:
                        continue
                    except Exception as e:
                        logger.warning("get_message error: %s", e, exc_info=True)
                        await asyncio.sleep(1)
                        continue

                    if message is None:
                        continue

                    channel = message["channel"]
                    try:
                        data = json.loads(message["data"])
                    except json.JSONDecodeError:
                        continue

                    # Periodic maintenance
                    now = asyncio.get_event_loop().time()
                    if now - self._last_reload > self._reload_interval:
                        await self._load_bot_config()
                        collected = gc.collect()
                        logger.info(
                            "Maintenance: bot config reloaded, gc collected %d objects",
                            collected,
                        )
                        self._last_reload = now

                    pair = data.get("pair", "")
                    if not pair:
                        continue

                    if channel == "channel:signal:mapped":
                        # Buffer the mapped signal — will be sent in sorted order
                        await self._add_to_buffer(data)

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

    # Cleanup Redis lock on exit
    try:
        import redis as sync_redis
        r = sync_redis.Redis.from_url("redis://localhost:6379/0", decode_responses=True)
        r.delete("service:lock:notification_bot")
        r.close()
    except Exception:
        pass


def run():
    """Convenience entry point: create notifier and run forever."""
    import redis as sync_redis

    # Dup guard: check Redis lock
    LOCK_KEY = "service:lock:notification_bot"
    try:
        r = sync_redis.Redis.from_url("redis://localhost:6379/0", decode_responses=True)
        existing = r.get(LOCK_KEY)
        if existing:
            logger.warning("Another notification_bot is already running (lock=%s) - exiting", existing)
            return
        r.set(LOCK_KEY, "pid=%d" % os.getpid(), ex=30)
        r.close()
    except Exception as e:
        logger.warning("Dup guard Redis unavailable, continuing anyway: %s", e)
    notifier = SignalNotifier()
    notifier._running = True

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    def _stop():
        logger.info("Shutting down SignalNotifier...")
        notifier._running = False

    for sig in (signal_module.SIGINT, signal_module.SIGTERM):
        try:
            loop.add_signal_handler(sig, _stop)
        except (NotImplementedError, ValueError):
            pass

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
