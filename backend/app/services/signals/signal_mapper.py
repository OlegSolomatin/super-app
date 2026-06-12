"""Signal mapper — classifies trading signals and maps them to strategies.

Determines signal type (ёршик/лесенка/дисбаланс/всплеск объёма),
maps to the correct engine (OB or Trading) with recommended parameters,
and performs cross-exchange lookup for signals from unsupported exchanges.
"""

from __future__ import annotations

import asyncio
import logging
import time
from dataclasses import dataclass, field
from typing import Optional

logger = logging.getLogger(__name__)

# ── In-memory exchange check cache ────────────────────────────────────────
_EXCHANGE_CACHE: dict[str, tuple[bool, float]] = {}  # key -> (result, timestamp)
_EXCHANGE_CACHE_TTL = 300  # 5 minutes


def _cache_get(key: str) -> Optional[bool]:
    """Get cached exchange check result if still fresh."""
    entry = _EXCHANGE_CACHE.get(key)
    if entry is None:
        return None
    result, ts = entry
    if time.monotonic() - ts > _EXCHANGE_CACHE_TTL:
        del _EXCHANGE_CACHE[key]
        return None
    return result


def _cache_set(key: str, result: bool):
    """Cache an exchange check result with current timestamp."""
    _EXCHANGE_CACHE[key] = (result, time.monotonic())


@dataclass
class SignalClassification:
    """Result of classifying a trading signal."""

    signal_type: str  # brush / stair / imbalance_top / imbalance_bot / volume_spike
    signal_label: str  # Ёршик / Лесенка / Дисбаланс ⬆ / Дисбаланс ⬇ / Всплеск объёма

    mapped_engine: str  # "ob" or "trading"
    mapped_strategy: str

    params: dict = field(default_factory=dict)
    fallback_exchange: Optional[str] = None  # Alternative exchange found
    confidence: float = 0.0  # How confident (0-1)


def classify_signal(
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
    """Classify a trading signal into a strategy.

    Args:
        channel: 'brushscreener' or 'stairscreener'
        exchange: Exchange name (Mexc, Gate, etc.)
        pair: Trading pair (WOJAKUSDT)
        price_range: Price movement range in percent
        vol_60m: Volume over 60 minutes in USD
        vol_10m: Volume over 10 minutes in USD
        slope: Stair slope value (stairscreener only)
        top_ratio: Top touch ratio (brushscreener only)
        bot_ratio: Bottom touch ratio (brushscreener only)

    Returns:
        SignalClassification with type, engine, strategy and params.
    """
    # ── Stairscreener: лесенка ──────────────────────────────────────────
    if channel == "stairscreener" and slope is not None and slope > 3.0:
        return _classify_stair(price_range, vol_60m, vol_10m, slope)

    # ── Brushscreener: ёршик или дисбаланс ──────────────────────────────
    if channel == "brushscreener" and top_ratio is not None and bot_ratio is not None:
        return _classify_brush(price_range, vol_60m, vol_10m, top_ratio, bot_ratio)

    # ── Volume spike detection (any channel) ────────────────────────────
    if vol_10m and vol_60m and vol_60m > 0 and (vol_10m / vol_60m) > 0.3:
        return _classify_volume_spike(price_range, vol_60m, vol_10m)

    # ── Fallback: unknown ───────────────────────────────────────────────
    return SignalClassification(
        signal_type="unknown",
        signal_label="Неизвестный",
        mapped_engine="trading",
        mapped_strategy="rsi_ma_combo",
        params=_default_trading_params(),
        confidence=0.1,
    )


def _classify_stair(
    price_range: Optional[float],
    vol_60m: Optional[float],
    vol_10m: Optional[float],
    slope: float,
) -> SignalClassification:
    """Classify a stair signal."""
    # Higher slope = stronger trend
    if slope > 8:
        confidence = 0.9
        sl = 3.0
        tp = 6.0
    elif slope > 5:
        confidence = 0.7
        sl = 2.0
        tp = 5.0
    else:
        confidence = 0.5
        sl = 1.5
        tp = 4.0

    return SignalClassification(
        signal_type="stair",
        signal_label="Лесенка",
        mapped_engine="trading",
        mapped_strategy="stair_climber",
        params={
            "timeframe": "3m",
            "leverage": 3,
            "balance": 10.0,
            "max_trade": 5.0,
            "stoploss": sl,
            "takeprofit": tp,
            "duration": 1,
            "slope": slope,
        },
        confidence=min(confidence, 0.95),
    )


def _classify_brush(
    price_range: Optional[float],
    vol_60m: Optional[float],
    vol_10m: Optional[float],
    top_ratio: float,
    bot_ratio: float,
) -> SignalClassification:
    """Classify a brush signal — could be erшик or imbalance."""
    ratio_diff = abs(top_ratio - bot_ratio)
    ratio_max = max(top_ratio, bot_ratio)

    # Ёршик: top/bot примерно равны, малый range
    if ratio_diff < ratio_max * 0.5 and (price_range is None or price_range < 3.0):
        return SignalClassification(
            signal_type="brush",
            signal_label="Ёршик",
            mapped_engine="ob",
            mapped_strategy="ers_scalping",
            params={
                "balance": 10.0,
                "max_open": 1,
                "stoploss": -1.5,
                "trailing_stop": 0.3,
                "max_hold": 120,
                "conf_ticks": 2,
                "max_spread": 0.1,
                "cooldown": 120,
                "auto_stop": 1,
                "ers_min_imbalance": 0.52,
                "ers_min_profit_pct": 0.01,
                "ers_exit_on_reversion": True,
                "ers_max_hold": 60,
            },
            confidence=0.8,
        )

    # Дисбаланс: одна сторона доминирует
    if bot_ratio > top_ratio * 1.5:
        # Bottom touches dominate → накопление → upward breakout
        return SignalClassification(
            signal_type="imbalance_bot",
            signal_label="Дисбаланс ⬆",
            mapped_engine="ob",
            mapped_strategy="imbalance_scalping",
            params={
                "balance": 10.0,
                "max_open": 1,
                "stoploss": -2.0,
                "max_hold": 120,
                "imbalance_threshold": 0.7,
                "surge_pct": 2.0,
            },
            confidence=0.75,
        )

    if top_ratio > bot_ratio * 1.5:
        # Top touches dominate → распределение → downward breakout
        return SignalClassification(
            signal_type="imbalance_top",
            signal_label="Дисбаланс ⬇",
            mapped_engine="ob",
            mapped_strategy="imbalance_scalping",
            params={
                "balance": 10.0,
                "max_open": 1,
                "stoploss": -2.0,
                "max_hold": 120,
                "imbalance_threshold": 0.7,
                "surge_pct": 2.0,
            },
            confidence=0.7,
        )

    # Fallback: эршик по умолчанию
    return SignalClassification(
        signal_type="brush",
        signal_label="Ёршик",
        mapped_engine="ob",
        mapped_strategy="ers_scalping",
        params=_default_ob_params(),
        confidence=0.5,
    )


def _classify_volume_spike(
    price_range: Optional[float],
    vol_60m: Optional[float],
    vol_10m: Optional[float],
) -> SignalClassification:
    """Classify a volume spike signal."""
    return SignalClassification(
        signal_type="volume_spike",
        signal_label="Всплеск объёма",
        mapped_engine="ob",
        mapped_strategy="order_flow_momentum",
        params={
            "balance": 10.0,
            "max_open": 1,
            "stoploss": -2.0,
            "max_hold": 120,
            "conf_ticks": 3,
            "flow_threshold": 10000,
            "min_flow_signals": 3,
        },
        confidence=0.6,
    )


def _default_trading_params() -> dict:
    return {
        "timeframe": "3m",
        "leverage": 3,
        "balance": 10.0,
        "max_trade": 5.0,
        "stoploss": 2.0,
        "takeprofit": 5.0,
        "duration": 1,
    }


def _default_ob_params() -> dict:
    return {
        "balance": 10.0,
        "max_open": 1,
        "stoploss": -1.5,
        "trailing_stop": 0.3,
        "max_hold": 120,
        "conf_ticks": 2,
        "max_spread": 0.1,
        "cooldown": 120,
        "auto_stop": 1,
    }


async def check_cross_exchange(pair: str, source_exchange: str) -> Optional[str]:
    """Check if a trading pair exists on Binance (for cross-exchange lookup).

    Args:
        pair: Trading pair (WOJAKUSDT)
        source_exchange: Original exchange (Mexc, Gate, etc.)

    Returns:
        'binance' if pair exists on Binance, None otherwise.
    """
    # If already on Binance, no lookup needed
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

    Queries the exchange_keys table for active valid keys,
    then checks pair availability on each unique exchange in parallel.

    Args:
        pair: Trading pair (WOJAKUSDT)
        session: SQLAlchemy async session

    Returns:
        Dict of {exchange_name: bool} — whether pair is available on that exchange.
    """
    from sqlalchemy import select
    from app.models.exchange_key import ExchangeKey

    # Get active valid keys (unique exchanges)
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
        """Check a single exchange — cached if recently checked."""
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
                logger.warning("No ticker check implemented for %s", exchange_name)
                return exchange_name, False

            ticker = await ex.get_ticker(pair)
            available = bool(ticker and ticker.get("volume", 0) > 0)
            _cache_set(cache_key, available)
            logger.info("Exchange check %s/%s: %s", exchange_name, pair, "✅" if available else "❌")
            return exchange_name, available

        except Exception as e:
            logger.warning("Exchange check failed for %s/%s: %s", exchange_name, pair, e)
            return exchange_name, False

    # Run all exchange checks in PARALLEL
    results_list = await asyncio.gather(
        *[_check_one(ex) for ex in exchanges],
        return_exceptions=False,
    )
    return dict(results_list)


async def map_and_save_signal(
    session,
    signal_id: int,
) -> Optional[SignalClassification]:
    """Classify a signal and save mapped_* fields to DB.

    Args:
        session: SQLAlchemy async session
        signal_id: TradingSignal ID

    Returns:
        SignalClassification or None if signal not found.
    """
    from sqlalchemy import select

    from app.models.trading_signal import TradingSignal

    stmt = select(TradingSignal).where(TradingSignal.id == signal_id)
    result = await session.execute(stmt)
    signal = result.scalar_one_or_none()

    if signal is None:
        logger.warning("Signal #%d not found for mapping", signal_id)
        return None

    # Classify
    classification = classify_signal(
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

    # Cross-exchange + available exchanges — IN PARALLEL
    fallback_task = asyncio.create_task(
        check_cross_exchange(signal.pair, signal.exchange)
    )
    avail_task = asyncio.create_task(
        check_available_exchanges(signal.pair, session)
    )
    fallback, available_exchanges = await asyncio.gather(
        fallback_task, avail_task
    )
    classification.fallback_exchange = fallback

    # Save to DB
    signal.mapped_strategy = classification.mapped_strategy
    signal.mapped_engine = classification.mapped_engine
    signal.mapped_params = classification.params
    signal.mapped_exchange_fallback = fallback
    signal.mapped_available_exchanges = available_exchanges
    await session.commit()

    # Publish mapped signal to Redis pub/sub
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
        })
    except Exception as e:
        logger.warning("Redis pub/sub unavailable (skip mapped publish): %s", e)

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
