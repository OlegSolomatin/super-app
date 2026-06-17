"""Signal mapper — classifies trading signals via LLM and maps them to strategies.

Architecture:
  1. Parser finds signal → saves to DB → publishes raw to Redis
  2. This module classifies via LLM with exactly 2 strategy options per channel
  3. Checks pair availability on user's exchanges
  4. Publishes classified signal back to Redis
"""
from __future__ import annotations

import asyncio
import json
import logging
import time
from dataclasses import dataclass, field
from typing import Any, Optional

import httpx

from app.core.config import settings

logger = logging.getLogger(__name__)

# ── LLM config ──────────────────────────────────────────────────────────────

_LLM_API_URL = "https://api.deepseek.com/v1/chat/completions"
_LLM_MODEL = "deepseek-chat"  # Fast model for signal classification
_LLM_TIMEOUT = 8  # seconds
_LLM_TEMPERATURE = 0.1

# ── In-memory exchange check cache ────────────────────────────────────────

_EXCHANGE_CACHE: dict[str, tuple[bool, float]] = {}
_EXCHANGE_CACHE_TTL = 300  # 5 minutes


def _cache_get(key: str) -> Optional[bool]:
    entry = _EXCHANGE_CACHE.get(key)
    if entry is None:
        return None
    result, ts = entry
    if time.monotonic() - ts > _EXCHANGE_CACHE_TTL:
        del _EXCHANGE_CACHE[key]
        return None
    return result


def _cache_set(key: str, result: bool):
    _EXCHANGE_CACHE[key] = (result, time.monotonic())


# ── SignalClassification dataclass ─────────────────────────────────────────


@dataclass
class SignalClassification:
    """Result of classifying a trading signal."""

    signal_type: str  # brush / stair / imbalance_top / imbalance_bot / volume_spike / hybrid / unknown
    signal_label: str  # Ёршик / Лесенка / Дисбаланс ⬆ / Дисбаланс ⬇ / Всплеск объЪма / Смешанный

    mapped_engine: str  # "ob" or "trading"
    mapped_strategy: str

    params: dict = field(default_factory=dict)
    fallback_exchange: Optional[str] = None
    confidence: float = 0.0
    reasoning: str = ""
    direction: str = "long"  # long / short
    current_price: Optional[float] = None  # LLM reasoning why this choice


# ── Core: classify via LLM ─────────────────────────────────────────────────


async def _llm_classify(prompt: str) -> Optional[SignalClassification]:
    """Send classification prompt to LLM and parse response.

    Args:
        prompt: Built prompt from strategy_config.build_llm_prompt()

    Returns:
        SignalClassification or None if LLM failed.
    """
    if not settings.DEEPSEEK_API_KEY:
        logger.error("DEEPSEEK_API_KEY not configured")
        return None

    messages = [
        {
            "role": "system",
            "content": "Ты — классификатор торговых сигналов для крипто-трейдинга. "
            "Отвечай строго в JSON формате. Выбирай одну из двух предложенных стратегий.",
        },
        {"role": "user", "content": prompt},
    ]

    payload = {
        "model": _LLM_MODEL,
        "messages": messages,
        "temperature": _LLM_TEMPERATURE,
        "max_tokens": 200,
        "response_format": {"type": "json_object"},
    }

    try:
        async with httpx.AsyncClient(timeout=_LLM_TIMEOUT) as client:
            resp = await client.post(
                _LLM_API_URL,
                headers={
                    "Authorization": f"Bearer {settings.DEEPSEEK_API_KEY}",
                    "Content-Type": "application/json",
                },
                json=payload,
            )
            resp.raise_for_status()
            data = resp.json()
            content = data["choices"][0]["message"]["content"]
    except httpx.TimeoutException:
        logger.warning("LLM classify: timeout after %ds", _LLM_TIMEOUT)
        return None
    except Exception as e:
        logger.warning("LLM classify failed: %s", e)
        return None

    # Parse JSON from LLM response
    try:
        result = json.loads(content)
    except json.JSONDecodeError:
        logger.warning("LLM classify: invalid JSON response: %s", content[:200])
        return None

    strategy_id = result.get("strategy", "").strip()
    confidence = max(0.0, min(1.0, float(result.get("confidence", 0.5))))
    params = result.get("params", {})
    reasoning = result.get("reasoning", "")

    # Derive signal_type from strategy + variant
    variant = result.get("variant", "A")
    signal_type = _derive_signal_type(strategy_id, variant)

    return SignalClassification(
        signal_type=signal_type,
        signal_label=_derive_label(strategy_id, variant),
        mapped_engine=_derive_engine(strategy_id),
        mapped_strategy=strategy_id,
        params=params,
        confidence=confidence,
        reasoning=reasoning,
    )


# ── Helpers ────────────────────────────────────────────────────────────────


def _derive_signal_type(strategy_id: str, variant: str) -> str:
    mapping = {
        "ers_scalping": "brush",
        "imbalance_scalping": "imbalance_bot",
        "stair_climber": "stair",
        "order_flow_momentum": "volume_spike",
        "rsi_ma_combo": "hybrid",
        "supertrend": "hybrid",
    }
    return mapping.get(strategy_id, "unknown")


def _derive_label(strategy_id: str, variant: str) -> str:
    mapping = {
        "ers_scalping": "Ёршик",
        "imbalance_scalping": "Дисбаланс ⬆",
        "stair_climber": "Лесенка",
        "order_flow_momentum": "Всплеск объёма",
        "rsi_ma_combo": "Смешанный",
        "supertrend": "Смешанный",
    }
    return mapping.get(strategy_id, "Неизвестный")


def _derive_engine(strategy_id: str) -> str:
    ob_strategies = {"ers_scalping", "imbalance_scalping", "order_flow_momentum"}
    return "ob" if strategy_id in ob_strategies else "trading"


# ── Public API ──────────────────────────────────────────────────────────────


async def classify_signal(
    channel: str,
    exchange: str,
    pair: str,
    price_range: Optional[float] = None,
    vol_60m: Optional[float] = None,
    vol_10m: Optional[float] = None,
    slope: Optional[float] = None,
    top_ratio: Optional[float] = None,
    bot_ratio: Optional[float] = None,
) -> SignalClassification:
    """Classify a trading signal via LLM with 2 strategy options.

    Falls back to volume spike detection if LLM fails or returns unknown.
    Falls back to default trading strategy if all else fails.
    """
    from app.services.signals.strategy_config import build_llm_prompt

    # Try LLM
    prompt = build_llm_prompt(
        channel=channel,
        pair=pair,
        price_range=price_range,
        vol_60m=vol_60m,
        vol_10m=vol_10m,
        slope=slope,
        top_ratio=top_ratio,
        bot_ratio=bot_ratio,
    )

    if prompt:
        llm_result = await _llm_classify(prompt)
        if llm_result and llm_result.confidence >= 0.3:
            if llm_result.mapped_strategy and llm_result.mapped_strategy != "unknown":
                return llm_result

    # Fallback 1: volume spike detection (any channel)
    if vol_10m and vol_60m and vol_60m > 0 and (vol_10m / vol_60m) > 0.3:
        return SignalClassification(
            signal_type="volume_spike",
            signal_label="Всплеск объёма",
            mapped_engine="ob",
            mapped_strategy="order_flow_momentum",
            params={"balance": 10.0, "max_open": 1, "stoploss": -2.0, "max_hold": 120},
            confidence=0.5,
            reasoning="LLM не ответил, определён по всплеску объёма vol10m/vol60m",
        )

    # Fallback 2: unknown — send to default trading
    return SignalClassification(
        signal_type="unknown",
        signal_label="Неизвестный",
        mapped_engine="trading",
        mapped_strategy="rsi_ma_combo",
        params={"timeframe": "3m", "balance": 10.0, "stoploss": 2.0, "takeprofit": 5.0},
        confidence=0.2,
        reasoning="LLM не ответил, назначена стратегия по умолчанию",
    )


# ── Cross-exchange & availability checks ───────────────────────────────────


async def check_cross_exchange(pair: str, source_exchange: str) -> Optional[str]:
    """Check if a trading pair exists on Binance (for cross-exchange lookup)."""
    if "binance" in source_exchange.lower():
        return None

    cache_key = f"cross:{pair.upper()}"
    cached = _cache_get(cache_key)
    if cached is not None:
        return "binance" if cached else None

    try:
        from app.services.trading.exchange.binance import BinanceExchange

        exchange = BinanceExchange()
        ticker = await exchange.get_ticker(pair)

        available = bool(ticker and ticker.get("volume", 0) > 0)
        _cache_set(cache_key, available)

        if available:
            logger.info("Cross-exchange: %s found on Binance (vol=$%.0f)", pair, ticker["volume"])
            return "binance"

        logger.info("Cross-exchange: %s not found on Binance (no volume)", pair)
        return None
    except Exception as e:
        logger.warning("Cross-exchange lookup failed for %s: %s", pair, e)
        return None


async def check_available_exchanges(
    pair: str,
    session,
) -> dict[str, bool]:
    """Check which user-connected exchanges have the trading pair.

    Reads active valid keys from exchange_keys table,
    then checks pair availability on each exchange in parallel.
    """
    from sqlalchemy import select
    from app.models.exchange_key import ExchangeKey

    stmt = (
        select(ExchangeKey.exchange)
        .where(ExchangeKey.status == "valid")
        .distinct()
    )
    result = await session.execute(stmt)
    exchanges = [row[0] for row in result]

    if not exchanges:
        logger.info("No active exchange keys found for availability check")
        return {}

    logger.info("Checking availability for %s on exchanges: %s", pair, exchanges)

    async def _check_one(exchange_name: str) -> tuple[str, bool]:
        cache_key = f"avail:{exchange_name}:{pair.upper()}"
        cached = _cache_get(cache_key)
        if cached is not None:
            return exchange_name, cached

        try:
            if exchange_name == "binance":
                from app.services.trading.exchange.binance import BinanceExchange
                ex = BinanceExchange()
            elif exchange_name == "bybit":
                from app.services.trading.exchange.bybit import BybitExchange
                ex = BybitExchange()
            else:
                from app.services.trading.exchange.ccxt_exchange import CCXTExchange
                ex = CCXTExchange(exchange_name)

            ticker = await ex.get_ticker(pair)
            available = bool(ticker and ticker.get("volume", 0) > 0)
            _cache_set(cache_key, available)
            logger.info("Exchange check %s/%s: %s", exchange_name, pair, "✅" if available else "❌")
            return exchange_name, available

        except Exception as e:
            logger.warning("Exchange check failed for %s/%s: %s", exchange_name, pair, e)
            return exchange_name, False

    results_list = await asyncio.gather(
        *[_check_one(ex) for ex in exchanges],
        return_exceptions=False,
    )
    return dict(results_list)


# ── Main pipeline: map → save → publish ──────────────────────────────────


async def map_and_save_signal(
    session,
    signal_id: int,
) -> Optional[SignalClassification]:
    """Classify a signal, save mapped_* fields to DB, publish to Redis.

    Args:
        session: SQLAlchemy async session
        signal_id: TradingSignal ID

    Returns:
        SignalClassification or None if signal not found or already classified.
    """
    from sqlalchemy import select
    from app.models.trading_signal import TradingSignal

    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one_or_none()

    if signal is None:
        logger.warning("Signal #%d not found for mapping", signal_id)
        return None

    # ── Dedup: skip if already classified ────────────────────────────────
    if signal.mapped_strategy is not None:
        logger.info(
            "Signal #%d already classified as %s, skipping",
            signal_id,
            signal.mapped_strategy,
        )
        return None

    # ── Classify via LLM ────────────────────────────────────────────────
    t0 = time.monotonic()
    classification = await classify_signal(
        channel=signal.channel,
        exchange=signal.exchange,
        pair=signal.pair,
        price_range=signal.price_range,
        vol_60m=signal.vol_60m,
        vol_10m=signal.vol_10m,
        slope=signal.slope,
        top_ratio=signal.top_ratio,
        bot_ratio=signal.bot_ratio,
    )
    t1 = time.monotonic()
    logger.info(
        "Signal #%d: LLM classification in %.0fms → %s/%s (conf=%.2f)",
        signal_id,
        (t1 - t0) * 1000,
        classification.mapped_engine,
        classification.mapped_strategy,
        classification.confidence,
    )

    # ── Cross-exchange + available exchanges + price — IN PARALLEL ──────
    fallback_task = asyncio.create_task(
        check_cross_exchange(signal.pair, signal.exchange)
    )
    avail_task = asyncio.create_task(
        check_available_exchanges(signal.pair, session)
    )

    # Fetch current price from the first available exchange
    async def _fetch_price():
        for exch_name in ["binance", "bybit"]:
            try:
                if exch_name == "binance":
                    from app.services.trading.exchange.binance import BinanceExchange
                    ex = BinanceExchange()
                elif exch_name == "bybit":
                    from app.services.trading.exchange.bybit import BybitExchange
                    ex = BybitExchange()
                else:
                    continue
                ticker = await ex.get_ticker(signal.pair)
                if ticker and ticker.get("lastPrice"):
                    return float(ticker["lastPrice"])
            except Exception:
                continue
        return None

    price_task = asyncio.create_task(_fetch_price())
    fallback, available_exchanges, current_price = await asyncio.gather(
        fallback_task, avail_task, price_task
    )
    classification.fallback_exchange = fallback
    classification.current_price = current_price

    # Derive direction from signal_type
    if classification.signal_type == "imbalance_top":
        classification.direction = "short"
    elif classification.signal_type == "imbalance_bot":
        classification.direction = "long"
    elif classification.signal_type == "stair":
        classification.direction = "long"
    elif classification.signal_type == "brush":
        classification.direction = "long"
    elif classification.signal_type == "volume_spike":
        classification.direction = "long"

    # ── Save to DB ──────────────────────────────────────────────────────
    signal.mapped_strategy = classification.mapped_strategy
    signal.mapped_engine = classification.mapped_engine
    signal.mapped_params = classification.params
    signal.mapped_exchange_fallback = fallback
    signal.mapped_available_exchanges = available_exchanges
    signal.mapped_confidence = classification.confidence
    signal.mapped_reasoning = classification.reasoning
    await session.commit()

    # ── Publish mapped signal to Redis pub/sub ──────────────────────────
    try:
        from app.core.cache import publish

        await publish("channel:signal:mapped", {
            "id": signal.id,
            "pair": signal.pair,
            "channel": signal.channel,
            "exchange": signal.exchange,
            "signal_type": classification.signal_type,
            "signal_label": classification.signal_label,
            "mapped_engine": classification.mapped_engine,
            "mapped_strategy": classification.mapped_strategy,
            "mapped_params": classification.params,
            "fallback_exchange": fallback,
            "confidence": classification.confidence,
            "available_exchanges": available_exchanges,
            "reasoning": classification.reasoning,
            "direction": classification.direction,
            "current_price": classification.current_price,
        })
    except Exception as e:
        logger.warning("Redis pub/sub unavailable (skip mapped publish): %s", e)

    # ── Update signals:latest in Redis ──────────────────────────────────
    try:
        from redis.asyncio import Redis as AsyncRedis

        r = AsyncRedis.from_url(settings.REDIS_URL, encoding="utf-8", decode_responses=True)
        try:
            updated_entry = {
                "id": signal.id,
                "channel": signal.channel,
                "exchange": signal.exchange,
                "pair": signal.pair,
                "price_range": signal.price_range,
                "vol_60m": signal.vol_60m,
                "vol_10m": signal.vol_10m,
                "slope": signal.slope,
                "top_ratio": signal.top_ratio,
                "bot_ratio": signal.bot_ratio,
                "mapped_strategy": signal.mapped_strategy,
                "mapped_engine": signal.mapped_engine,
                "mapped_exchange_fallback": signal.mapped_exchange_fallback,
                "mapped_available_exchanges": signal.mapped_available_exchanges,
                "is_processed": signal.is_processed if hasattr(signal, "is_processed") else False,
                "created_at": signal.created_at.isoformat() if signal.created_at else None,
            }
            signal_json = json.dumps(updated_entry)
            old_entries = await r.lrange("signals:latest", 0, -1)
            for entry in old_entries:
                try:
                    parsed = json.loads(entry)
                    if parsed.get("id") == signal.id:
                        await r.lrem("signals:latest", 1, entry)
                except (json.JSONDecodeError, TypeError):
                    continue
            await r.lpush("signals:latest", signal_json)
            await r.ltrim("signals:latest", 0, 49)
        finally:
            await r.aclose()
    except Exception as e:
        logger.warning("Failed to update signals:latest in Redis: %s", e)

    logger.info(
        "Mapped signal #%d (%s %s): %s → %s/%s (fallback=%s, conf=%.2f)",
        signal_id,
        signal.channel,
        signal.pair,
        classification.signal_label,
        classification.mapped_engine,
        classification.mapped_strategy,
        fallback or "none",
        classification.confidence,
    )

    return classification
