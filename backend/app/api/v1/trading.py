"""Trading API endpoints.

GET    /trading/pairs               — Available trading pairs (hardcoded)
GET    /trading/strategies          — Available strategies (hardcoded)
GET    /trading/exchanges           — Available exchanges (hardcoded)
POST   /trading/runs                — Start a new trading run
GET    /trading/runs                — List all runs (filter by status)
GET    /trading/runs/{run_id}       — Run details
GET    /trading/runs/{run_id}/trades— Trades for a run
GET    /trading/runs/{run_id}/code  — Strategy code/logic
DELETE /trading/runs/{run_id}       — Stop/delete a run
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.core.database import get_session
from app.core.dependencies import get_current_user
from app.models.trading import TradingConfig as DBTradingConfig
from app.models.trading import TradingResult as DBTradingResult
from app.models.trading import TradingRun as DBTradingRun
from app.models.trading import TradingTrade as DBTradingTrade
from app.models.user import User
from app.schemas.trading import (
    ExchangeInfo,
    ExchangesListResponse,
    PairInfo,
    PairInsightResponse,
    PairsListResponse,
    PairsLiveDataResponse,
    StrategiesListResponse,
    StrategyInfo,
    StrategyScore,
    TradeListResponse,
    TradeResponse,
    TradingConfig,
    TradingResultResponse,
    TradingRunListResponse,
    TradingRunResponse,
    TradingRunStatus,
)
from app.services.trading.models import (
    TradingConfig as DomainTradingConfig,
    TradingRunMode,
)
from app.services.trading.scheduler import scheduler

router = APIRouter(prefix="/trading", tags=["trading"])

# ---------------------------------------------------------------------------
# Hardcoded pair list
# ---------------------------------------------------------------------------
from app.services.trading.pair_list import COIN_ICON_NAMES, get_coin_icon_url, fetch_all_usdt_pairs, fetch_24h_volumes, fetch_24h_tickers

HARDCODED_PAIRS = [
    PairInfo(symbol="BTCUSDT", base="BTC", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="ETHUSDT", base="ETH", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="BNBUSDT", base="BNB", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="SOLUSDT", base="SOL", quote="USDT", min_qty=0.1, tick_size=0.01),
    PairInfo(symbol="XRPUSDT", base="XRP", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ADAUSDT", base="ADA", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="DOGEUSDT", base="DOGE", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="AVAXUSDT", base="AVAX", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="DOTUSDT", base="DOT", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="MATICUSDT", base="MATIC", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="LTCUSDT", base="LTC", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="LINKUSDT", base="LINK", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="UNIUSDT", base="UNI", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ATOMUSDT", base="ATOM", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ETCUSDT", base="ETC", quote="USDT", min_qty=0.1, tick_size=0.01),
    PairInfo(symbol="FILUSDT", base="FIL", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="TRXUSDT", base="TRX", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="XLMUSDT", base="XLM", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="VETUSDT", base="VET", quote="USDT", min_qty=1.0, tick_size=0.000001),
    PairInfo(symbol="ALGOUSDT", base="ALGO", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="NEARUSDT", base="NEAR", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="FTMUSDT", base="FTM", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="SANDUSDT", base="SAND", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="MANAUSDT", base="MANA", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="AXSUSDT", base="AXS", quote="USDT", min_qty=0.01, tick_size=0.001),
    PairInfo(symbol="APEUSDT", base="APE", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="SHIBUSDT", base="SHIB", quote="USDT", min_qty=100000, tick_size=0.00000001),
    PairInfo(symbol="CROUSDT", base="CRO", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="EOSUSDT", base="EOS", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ICXUSDT", base="ICX", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="ZECUSDT", base="ZEC", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="XMRUSDT", base="XMR", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="DASHUSDT", base="DASH", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="ZILUSDT", base="ZIL", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="KSMUSDT", base="KSM", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="COMPUSDT", base="COMP", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="YFIUSDT", base="YFI", quote="USDT", min_qty=0.0001, tick_size=0.01),
    PairInfo(symbol="AAVEUSDT", base="AAVE", quote="USDT", min_qty=0.01, tick_size=0.01),
    PairInfo(symbol="MKRUSDT", base="MKR", quote="USDT", min_qty=0.001, tick_size=0.01),
    PairInfo(symbol="BATUSDT", base="BAT", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ENJUSDT", base="ENJ", quote="USDT", min_qty=1.0, tick_size=0.001),
    PairInfo(symbol="CHZUSDT", base="CHZ", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="ONEUSDT", base="ONE", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="ANKRUSDT", base="ANKR", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="IOSTUSDT", base="IOST", quote="USDT", min_qty=1.0, tick_size=0.00001),
    PairInfo(symbol="WAVESUSDT", base="WAVES", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="ONTUSDT", base="ONT", quote="USDT", min_qty=1.0, tick_size=0.0001),
    PairInfo(symbol="IOTAUSDT", base="IOTA", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="NANOUSDT", base="NANO", quote="USDT", min_qty=0.1, tick_size=0.001),
    PairInfo(symbol="LSKUSDT", base="LSK", quote="USDT", min_qty=0.1, tick_size=0.001),
]

async def _get_pair_list() -> list[PairInfo]:
    """Build pair list with icon_url populated from Binance."""
    hardcoded: dict[str, PairInfo] = {p.symbol: p for p in HARDCODED_PAIRS}
    symbols = await fetch_all_usdt_pairs()
    items: list[PairInfo] = []
    for symbol in symbols:
        if not symbol.endswith("USDT"):
            continue
        base = symbol[:-4]
        hard = hardcoded.get(symbol)
        items.append(PairInfo(
            symbol=symbol,
            base=base,
            quote="USDT",
            min_qty=hard.min_qty if hard else 0.001,
            tick_size=hard.tick_size if hard else 0.0001,
            icon_url=get_coin_icon_url(base),
        ))
    return items

# ---------------------------------------------------------------------------
# Hardcoded strategy list
# ---------------------------------------------------------------------------
HARDCODED_STRATEGIES = [
    StrategyInfo(
        name="all_pairs_hammer",
        description="🔍 Молот на всех парах — сканирует ВСЕ доступные USDT-пары и ищет паттерн Hammer на каждой. Только история, TF ≥ 30м.",
        type="pair_scanner",
        nuances=(
            "🔍 **Сканирование всех пар**\n\n"
            "📈 **Как работает:**\n"
            "• Проходит по всем USDT-парам из списка биржи\n"
            "• На каждой паре ищет паттерн Hammer (бычий разворот)\n"
            "• Открывает сделки на всех парах, где найден паттерн\n\n"
            "📊 **Рекомендуемый TF:** 30m+\n\n"
            "⚠️ **Только исторический режим**\n"
            "• Требует больше ресурсов ПК\n"
            "• SL: −1% / TP: динамический (полный диапазон свечи)"
        ),
        is_pair_scanner=True,
    ),
    StrategyInfo(
        name="all_pairs_inverse_hammer",
        description="🔍 Перевёрнутый Молот на всех парах — сканирует ВСЕ доступные USDT-пары и ищет паттерн Inverse Hammer на каждой. Только история, TF ≥ 30м.",
        type="pair_scanner",
        nuances=(
            "🔍 **Сканирование всех пар**\n\n"
            "📈 **Как работает:**\n"
            "• Проходит по всем USDT-парам из списка биржи\n"
            "• На каждой паре ищет паттерн Inverse Hammer (медвежий разворот)\n"
            "• Открывает сделки на всех парах, где найден паттерн\n\n"
            "📊 **Рекомендуемый TF:** 30m+\n\n"
            "⚠️ **Только исторический режим**\n"
            "• Требует больше ресурсов ПК\n"
            "• SL: −1% / TP: динамический (полный диапазон свечи)"
        ),
        is_pair_scanner=True,
    ),
    # ═══════════════════════════════════════════════════
    # Свечные паттерны
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="hammer",
        description="Молот — бычий разворотный паттерн. Маленькое тело, длинная нижняя тень. Трендовый фильтр (SMA200) отсекает ложные сигналы.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Тело свечи малое (≤30% от всего диапазона)\n"
            "• Нижняя тень ≥2× тела\n"
            "• Верхняя тень малая (≤10% от диапазона)\n"
            "• Свеча находится после нисходящего тренда\n\n"
            "📉 **Условия выхода:**\n"
            "• SL: −1% от цены входа\n"
            "• TP: динамический (полный диапазон свечи от входа)\n"
            "• Либо по сигналу Inverse Hammer\n\n"
            "⚙️ **Настройки:** SL: 1% | TP: dynamic (high−low) | Риск:Reward ~ 1:0.3–1.0\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="inverse_hammer",
        description="Перевёрнутый Молот — медвежий разворотный паттерн. Маленькое тело, длинная верхняя тень.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (SELL):**\n"
            "• Тело свечи малое (≤30% от всего диапазона)\n"
            "• Верхняя тень ≥2× тела\n"
            "• Нижняя тень малая (≤10% от диапазона)\n"
            "• Свеча находится после восходящего тренда\n\n"
            "📉 **Условия выхода:**\n"
            "• SL: +1% от цены входа (для шорта)\n"
            "• TP: динамический (полный диапазон свечи от входа)\n"
            "• Либо по сигналу Hammer\n\n"
            "⚙️ **Настройки:** SL: 1% | TP: dynamic (high−low) | Риск:Reward ~ 1:0.3–1.0\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="engulfing",
        description="Поглощение — бычий/медвежий разворотный паттерн. Тело текущей свечи полностью перекрывает тело предыдущей.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Текущая свеча бычья (close > open)\n"
            "• Тело текущей свечи полностью поглощает тело предыдущей\n"
            "• Предыдущая свеча медвежья (close < open)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Текущая свеча медвежья\n"
            "• Тело поглощает тело предыдущей бычьей свечи\n\n"
            "⚙️ **Таймфрейм:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="doji",
        description="Доджи — свеча с крошечным телом, сигнал неопределённости и потенциального разворота тренда.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Доджи после 2+ медвежьих свеч подряд\n"
            "• Тело доджи ≤5% от всего диапазона свечи\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Доджи после 2+ бычьих свеч подряд\n\n"
            "⚙️ **Таймфрейм:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="three_soldiers",
        description="Три солдата / Три вороны — паттерн из 3 свечей подтверждает сильный тренд.",
        type="candle_pattern",
        nuances=(
            "📈 **Условия входа (BUY) — Три белых солдата:**\n"
            "• 3 бычьих свечи подряд\n"
            "• Каждая закрывается выше предыдущей\n\n"
            "📉 **Условия входа (SELL) — Три чёрные вороны:**\n"
            "• 3 медвежьих свечи подряд\n"
            "• Каждая закрывается ниже предыдущей\n\n"
            "⚙️ **Таймфрейм:** 1h–4h"
        ),
    ),
    # ═══════════════════════════════════════════════════
    # Трендовые стратегии
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="ma_crossover",
        description="Пересечение скользящих средних — BUY при пересечении SMA50 выше SMA200, SELL при пересечении вниз.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• SMA(20) пересекает SMA(50) снизу вверх (золотое сечение)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• SMA(20) пересекает SMA(50) сверху вниз (смертельное сечение)\n\n"
            "⚙️ **Параметры:** SMA20 × SMA50\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="triple_ma",
        description="Три скользящие средние — вход по тренду при правильном порядке всех трёх MA.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• SMA(10) > SMA(30) > SMA(50) — восходящий тренд подтверждён\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• SMA(10) < SMA(30) < SMA(50) — нисходящий тренд\n\n"
            "⚙️ **Параметры:** SMA10 × SMA30 × SMA50\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="macd_crossover",
        description="MACD — пересечение MACD-линии с сигнальной. Классический трендовый индикатор.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• MACD-линия пересекает сигнальную снизу вверх\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• MACD-линия пересекает сигнальную сверху вниз\n\n"
            "⚙️ **Параметры:** MACD(12, 26, 9)\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="parabolic_sar",
        description="Parabolic SAR — точки под/над ценой определяют направление тренда. Переворотная стратегия.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• SAR под ценой — тренд вверх\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• SAR над ценой — тренд вниз\n\n"
            "⚙️ **Параметры:** ускорение 0.02, макс 0.20\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="adx",
        description="ADX — определяет силу тренда. Вход только при ADX > 25 в направлении сильного индекса (+DI или -DI).",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• ADX > 25 (сильный тренд)\n"
            "• +DI > -DI (направление вверх)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• ADX > 25\n"
            "• -DI > +DI (направление вниз)\n\n"
            "⚙️ **Параметры:** ADX(14)\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    StrategyInfo(
        name="supertrend",
        description="Supertrend — ATR-основанный индикатор тренда с переворотом. Надёжен на сильных движениях.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Цена пересекает нижнюю полосу Supertrend вверх\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Цена пересекает верхнюю полосу Supertrend вниз\n\n"
            "⚙️ **Параметры:** ATR(10), множитель 3\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
    # ═══════════════════════════════════════════════════
    # Осцилляторы / Разворотные
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="rsi_oversold",
        description="RSI — вход на перекупленности/перепроданности. BUY при RSI < 30, SELL при RSI > 70.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• RSI(14) < 30 — перепроданность (подтверждённая)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• RSI(14) > 70 — перекупленность (подтверждённая)\n\n"
            "⚙️ **Параметры:** RSI(14), пороги 30/70\n"

            "📊 **Рекомендуемый TF:** 1h"
        ),
    ),
    StrategyInfo(
        name="stochastic",
        description="Стохастик — %K и %D. BUY при %K < 20 и пересечении вверх, SELL при %K > 80 и пересечении вниз.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• %K < 20 (перепроданность)\n"
            "• %K пересекает %D снизу вверх\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• %K > 80 (перекупленность)\n"
            "• %K пересекает %D сверху вниз\n\n"
            "⚙️ **Параметры:** %K(14), %D(3)\n"

            "📊 **Рекомендуемый TF:** 1h"
        ),
    ),
    # ═══════════════════════════════════════════════════
    # Волатильность
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="bollinger_bands",
        description="Полосы Боллинджера — BUY при касании нижней полосы, SELL при касании верхней полосы.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Цена касается или пересекает нижнюю полосу (ожидание отскока)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Цена касается или пересекает верхнюю полосу (ожидание отката)\n\n"
            "⚙️ **Параметры:** BB(20, 2σ)\n"

            "📊 **Рекомендуемый TF:** 4h–1d"
        ),
    ),
    StrategyInfo(
        name="keltner_channels",
        description="Канал Кельтнера — EMA(20) ± ATR×2. BUY при пересечении верхней границы, SELL при нижней.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Цена пересекает верхнюю границу канала\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Цена пересекает нижнюю границу канала\n\n"
            "⚙️ **Параметры:** EMA(20), ATR(14), множитель 2\n"

            "📊 **Рекомендуемый TF:** 4h–1d"
        ),
    ),
    StrategyInfo(
        name="atr_breakout",
        description="ATR Breakout — пробой на ATR×1.5 от предыдущего закрытия. Волатильный пробой с подтверждением объёмом.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Close > prev_close + ATR×1.5 (пробой вверх)\n"
            "• Объём выше предыдущего\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Close < prev_close − ATR×1.5 (пробой вниз)\n"
            "• Объём выше предыдущего\n\n"
            "⚙️ **Параметры:** ATR(14), множитель 1.5\n"

            "📊 **Рекомендуемый TF:** 4h–1d"
        ),
    ),
    StrategyInfo(
        name="donchian",
        description="Дончиан — пробой 20-периодного максимума/минимума. Классический breakout-канал.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Close > highest high за 20 свечей (пробой вверх)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Close < lowest low за 20 свечей (пробой вниз)\n\n"
            "⚙️ **Параметры:** период 20\n"

            "📊 **Рекомендуемый TF:** 4h–1d"
        ),
    ),
    # ═══════════════════════════════════════════════════
    # Объёмные
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="vwap",
        description="VWAP — вход при отклонении цены на 2% от среднеобъёмной цены. BUY ниже VWAP, SELL выше.",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• Close < VWAP × 0.98 (недооценка на 2%)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• Close > VWAP × 1.02 (переоценка на 2%)\n\n"
            "⚙️ **Расчёт:** VWAP на всех доступных свечах\n"

            "📊 **Рекомендуемый TF:** 1h"
        ),
    ),
    StrategyInfo(
        name="obv",
        description="OBV — расхождение On-Balance Volume с ценой. BUY при росте OBV на падающей цене (накопление).",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• OBV растёт последние 5 свечей\n"
            "• Цена падает (бычья дивергенция)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• OBV падает последние 5 свечей\n"
            "• Цена растёт (медвежья дивергенция)\n\n"
            "⚙️ **Период сравнения:** 5 свечей\n"

            "📊 **Рекомендуемый TF:** 1h"
        ),
    ),
    # ═══════════════════════════════════════════════════
    # Комбинированные
    # ═══════════════════════════════════════════════════
    StrategyInfo(
        name="rsi_ma_combo",
        description="RSI + MA — комбинация осциллятора и тренда. BUY только при RSI < 35 в uptrend (close > SMA200).",
        type="indicator_based",
        nuances=(
            "📈 **Условия входа (BUY):**\n"
            "• RSI(14) < 35 (перепроданность)\n"
            "• Close > SMA(200) (восходящий тренд)\n\n"
            "📉 **Условия входа (SELL):**\n"
            "• RSI(14) > 65 (перекупленность)\n"
            "• Close < SMA(200) (нисходящий тренд)\n\n"
            "⚙️ **Параметры:** RSI(14), SMA(200), пороги 35/65\n"

            "📊 **Рекомендуемый TF:** 1h–4h"
        ),
    ),
]

# ---------------------------------------------------------------------------
# Hardcoded exchange list
# ---------------------------------------------------------------------------
HARDCODED_EXCHANGES = [
    ExchangeInfo(name="binance", display_name="Binance", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="bybit", display_name="Bybit", supports_history=True, supports_websocket=True),
    ExchangeInfo(name="mock", display_name="Мок (тест)", supports_history=True, supports_websocket=False),
]

# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------


@router.post("/runs/cleanup", response_model=dict)
async def cleanup_stale_runs(
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Mark stale 'running' runs as 'error' (they were orphaned by a restart)."""
    stmt = (
        select(DBTradingRun)
        .where(
            DBTradingRun.user_id == current_user.id,
            DBTradingRun.status == "running",
        )
    )
    result = await session.execute(stmt)
    runs = result.scalars().all()
    count = 0
    for run in runs:
        # Consider a run stale if the scheduler doesn't know about it
        if run.id not in scheduler.get_active_run_ids():
            run.status = "error"
            run.error = "Прерван перезапуском сервера"
            run.finished_at = datetime.now(timezone.utc)
            count += 1
    await session.commit()
    return {"cleaned": count}


@router.get("/pairs", response_model=PairsListResponse)
async def list_pairs(
    search: Optional[str] = Query(None, description="Filter by symbol substring"),
    sort: Optional[str] = Query(None, description="Sort order: 'liquidity' (by 24h volume)"),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=500, description="Items per page"),
) -> PairsListResponse:
    """Return available trading pairs with optional search, sort and pagination."""
    items = await _get_pair_list()

    # Sort by 24h liquidity (volume from Binance)
    if sort == "liquidity":
        volumes = await fetch_24h_volumes()
        items.sort(key=lambda p: volumes.get(p.symbol, 0), reverse=True)

    if search:
        search_upper = search.upper()
        items = [p for p in items if search_upper in p.symbol.upper()]
    total = len(items)
    offset = (page - 1) * page_size
    page_items = items[offset : offset + page_size]
    return PairsListResponse(items=page_items, total=total)


@router.get("/pairs/live", response_model=PairsLiveDataResponse)
async def list_pairs_live() -> PairsLiveDataResponse:
    """Return live 24hr data (price, volume, change %) for all USDT pairs."""
    tickers = await fetch_24h_tickers()
    return PairsLiveDataResponse(items=tickers)


def _calculate_volatility(high: float, low: float) -> float:
    """Calculate 24h volatility as percentage."""
    if high <= 0 or low <= 0:
        return 0.0
    mid = (high + low) / 2
    if mid <= 0:
        return 0.0
    return round(((high - low) / mid) * 100, 2)


def _compute_strategy_scores(
    volume: float, volatility: float, price: float,
) -> list[dict]:
    """Compute strategy recommendation scores for a pair."""
    results: list[dict] = []

    # Imbalance Scalping — high volatility
    vol_norm = min(volatility / 5.0, 1.0)  # 5%+ = 1.0
    imbalance_score = round(0.3 + 0.7 * vol_norm, 2)
    if imbalance_score > 0.5:
        reason = f"Волатильность {volatility}% — идеально для ловли дисбалансов в стакане"
    else:
        reason = f"Волатильность {volatility}% — низкая, сигналов может быть мало"
    results.append({
        "name": "imbalance_scalping",
        "label": "Imbalance Scalping",
        "score": min(imbalance_score, 0.95),
        "reason": reason,
    })

    # Spread Capture — low volatility, high volume
    vol_inv = max(1.0 - volatility / 3.0, 0.0)
    vol_norm_v = min(volume / 500_000_000, 1.0) if volume > 0 else 0
    spread_score = round(0.2 + 0.4 * vol_inv + 0.4 * vol_norm_v, 2)
    if spread_score > 0.5:
        reason = f"Спред узкий, объём ${_fmt_volume(volume)} — отлично для скальпирования"
    else:
        reason = f"Объём ${_fmt_volume(volume)} — для спред-торговли нужен стабильный поток"
    results.append({
        "name": "spread_capture",
        "label": "Spread Capture",
        "score": min(spread_score, 0.95),
        "reason": reason,
    })

    # Order Flow Momentum — high volume + medium volatility
    mom_score = round(0.2 + 0.5 * vol_norm_v + 0.3 * vol_norm, 2)
    if mom_score > 0.5:
        reason = f"Объём ${_fmt_volume(volume)} и волатильность {volatility}% — momentum-сигналы будут надёжными"
    else:
        reason = f"Низкий объём (${_fmt_volume(volume)}) — momentum может давать ложные сигналы"
    results.append({
        "name": "order_flow_momentum",
        "label": "Order Flow Momentum",
        "score": min(mom_score, 0.95),
        "reason": reason,
    })

    results.sort(key=lambda r: r["score"], reverse=True)
    return results

    # ЕРШ Scalping — любит высокий объём + любую волатильность (сверхчувствительный)
    ers_score = round(0.3 + 0.4 * vol_norm_v + 0.3 * vol_norm, 2)
    if ers_score > 0.5:
        reason = f"Объём ${_fmt_volume(volume)} и волатильность {volatility}% — ЕРШ будет ловить микро-движения"
    else:
        reason = f"Низкая активность — ЕРШ может не найти достаточно микро-сигналов"
    results.append({
        "name": "ers_scalping",
        "label": "ЕРШ Scalping",
        "score": min(ers_score, 0.95),
        "reason": reason,
    })

    results.sort(key=lambda r: r["score"], reverse=True)
    return results


def _fmt_volume(v: float) -> str:
    if v >= 1_000_000_000:
        return f"{v / 1_000_000_000:.1f}B"
    if v >= 1_000_000:
        return f"{v / 1_000_000:.1f}M"
    if v >= 1_000:
        return f"{v / 1_000:.1f}K"
    return f"{v:.0f}"


@router.get("/pairs/{symbol}/insight", response_model=PairInsightResponse)
async def pair_insight(symbol: str) -> PairInsightResponse:
    """Return market insight + strategy recommendations for a specific pair."""
    symbol = symbol.upper()
    if not symbol.endswith("USDT"):
        symbol = f"{symbol}USDT"

    tickers = await fetch_24h_tickers()
    data = tickers.get(symbol)
    if data is None:
        raise HTTPException(status_code=404, detail=f"Pair {symbol} not found")

    price = data["price"]
    volume = data["volume"]
    high = data.get("high", 0)
    low = data.get("low", 0)
    volatility = _calculate_volatility(high, low)

    # Approximate spread from ticker (not real OB spread)
    spread = round(volatility * 0.05, 2) if volatility > 0 else 0.01

    scores = _compute_strategy_scores(volume, volatility, price)

    return PairInsightResponse(
        symbol=symbol,
        price=price,
        volume_24h=volume,
        volatility_24h=volatility,
        spread=spread,
        recommended_strategies=[
            StrategyScore(**s) for s in scores
        ],
    )


@router.get("/strategies", response_model=StrategiesListResponse)
async def list_strategies() -> StrategiesListResponse:
    """Return available trading strategies."""
    return StrategiesListResponse(
        items=HARDCODED_STRATEGIES, total=len(HARDCODED_STRATEGIES)
    )


@router.get("/exchanges", response_model=ExchangesListResponse)
async def list_exchanges() -> ExchangesListResponse:
    """Return available exchange connectors."""
    return ExchangesListResponse(
        items=HARDCODED_EXCHANGES, total=len(HARDCODED_EXCHANGES)
    )


@router.post(
    "/runs",
    response_model=TradingRunResponse,
    status_code=status.HTTP_201_CREATED,
)
async def start_run(
    config: TradingConfig,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunResponse:
    """Start a new trading run with the given configuration.

    Creates a database record and schedules the run via the trading engine.
    """
    # Check scheduler capacity
    if not scheduler.can_start():
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Достигнут лимит одновременных запусков (15). Остановите активный запуск.",
        )

    # Create DB record
    db_run = DBTradingRun(
        user_id=current_user.id,
        status="running",
        mode=config.mode.value,
    )
    session.add(db_run)
    await session.flush()  # Get the run_id

    # Create config snapshot
    db_config = DBTradingConfig(
        run_id=db_run.id,
        pair="ALL" if config.strategy in ("all_pairs_hammer", "all_pairs_inverse_hammer") else config.pair,
        strategy=config.strategy,
        leverage=config.leverage,
        virtual_balance=config.virtual_balance,
        max_trade_amount=config.max_trade_amount,
        timeframe=config.timeframe,
        period_start=config.period_start,
        period_end=config.period_end,
        duration_days=config.duration_days,
        exchange=config.exchange,
        notification_bot_id=(
            UUID(config.notification_bot_id)
            if config.notification_bot_id
            else None
        ),
        stop_loss_percent=config.stop_loss_percent or 1.0,
        take_profit_percent=config.take_profit_percent or 5.0,
        trend_filter_enabled=config.trend_filter_enabled,
        trend_filter_period=config.trend_filter_period,
    )
    session.add(db_config)

    await session.commit()

    # Eagerly load relationships before validation
    stmt = (
        select(DBTradingRun)
        .options(
            selectinload(DBTradingRun.config),
            selectinload(DBTradingRun.result),
            selectinload(DBTradingRun.trades),
        )
        .where(DBTradingRun.id == db_run.id)
    )
    result = await session.execute(stmt)
    db_run = result.scalar_one()

    # Convert to domain config for the engine
    domain_config = DomainTradingConfig(
        mode=TradingRunMode(config.mode.value),
        pair="ALL" if config.strategy in ("all_pairs_hammer", "all_pairs_inverse_hammer") else config.pair,
        strategy=config.strategy,
        leverage=config.leverage,
        virtual_balance=config.virtual_balance,
        max_trade_amount=config.max_trade_amount,
        timeframe=config.timeframe,
        period_start=config.period_start,
        period_end=config.period_end,
        duration_days=config.duration_days,
        exchange=config.exchange,
        notification_bot_id=str(config.notification_bot_id) if config.notification_bot_id else None,
        stop_loss_percent=config.stop_loss_percent or 1.0,
        take_profit_percent=config.take_profit_percent or 5.0,
        trend_filter_enabled=config.trend_filter_enabled,
        trend_filter_period=config.trend_filter_period,
    )

    # Schedule the run (fire-and-forget via async task)
    # Scheduler creates its own DB session internally
    await scheduler.start_run(
        run_id=db_run.id,
        config=domain_config,
    )

    return TradingRunResponse.model_validate(db_run)


@router.get("/runs", response_model=TradingRunListResponse)
async def list_runs(
    status_filter: Optional[TradingRunStatus] = Query(
        None, alias="status", description="Filter by run status"
    ),
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=500, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunListResponse:
    """List all trading runs for the current user, with optional status filter."""
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config), selectinload(DBTradingRun.result))
        .where(DBTradingRun.user_id == current_user.id)
    )
    if status_filter:
        stmt = stmt.where(DBTradingRun.status == status_filter.value)
    stmt = stmt.order_by(DBTradingRun.started_at.desc())
    result = await session.execute(stmt)
    runs = result.scalars().all()
    total = len(runs)
    items = [TradingRunResponse.model_validate(r) for r in runs]
    total_pages = max(1, (total + page_size - 1) // page_size)
    return TradingRunListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/runs/{run_id}", response_model=TradingRunResponse)
async def get_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradingRunResponse:
    """Return details of a specific trading run."""
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config), selectinload(DBTradingRun.result))
        .where(
            DBTradingRun.id == run_id,
            DBTradingRun.user_id == current_user.id,
        )
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )
    return TradingRunResponse.model_validate(run)


@router.get("/runs/{run_id}/trades", response_model=TradeListResponse)
async def get_run_trades(
    run_id: int,
    page: int = Query(1, ge=1, description="Page number"),
    page_size: int = Query(20, ge=1, le=500, description="Items per page"),
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> TradeListResponse:
    """Return trades associated with a specific trading run."""
    # Verify the run exists and belongs to the user
    stmt = select(DBTradingRun).where(
        DBTradingRun.id == run_id,
        DBTradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    # Fetch trades from DB
    stmt = (
        select(DBTradingTrade)
        .where(DBTradingTrade.run_id == run_id)
        .order_by(DBTradingTrade.entry_time.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    )
    result = await session.execute(stmt)
    db_trades = result.scalars().all()

    # Get total count
    count_stmt = select(DBTradingTrade).where(DBTradingTrade.run_id == run_id)
    count_result = await session.execute(count_stmt)
    total = len(count_result.scalars().all())

    items = [TradeResponse.model_validate(t) for t in db_trades]
    total_pages = max(1, (total + page_size - 1) // page_size)

    return TradeListResponse(
        items=items,
        total=total,
        page=page,
        page_size=page_size,
        total_pages=total_pages,
    )


@router.get("/runs/{run_id}/scan-progress")
async def get_scan_progress(
    run_id: int,
    current_user: User = Depends(get_current_user),
) -> dict:
    """Return real-time scan progress for a pair-scanner run.

    Returns {
        "status": "scanning" | "done" | null,
        "total_pairs": int,
        "scanned_pairs": int,
        "trades_found": int,
        "pnl": float,
        "elapsed_seconds": float,
        "estimated_remaining_seconds": float,
        "current_pair": str,
    }
    Returns empty dict with status=null if not a scanner run.
    """
    progress = scheduler.get_scan_progress(run_id)
    if progress is None:
        return {"status": None}
    return progress


@router.get("/runs/{run_id}/code")
async def get_run_strategy_code(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> dict:
    """Return the strategy code/logic used by a trading run."""
    stmt = (
        select(DBTradingRun)
        .options(selectinload(DBTradingRun.config))
        .where(
            DBTradingRun.id == run_id,
            DBTradingRun.user_id == current_user.id,
        )
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    strategy_name = run.config.strategy if run.config else "unknown"

    # Return the strategy description from the hardcoded list
    strategy_desc = "Неизвестная стратегия"
    for s in HARDCODED_STRATEGIES:
        if s.name == strategy_name:
            strategy_desc = s.description
            break

    return {
        "run_id": run_id,
        "strategy": strategy_name,
        "description": strategy_desc,
        "code": f"# {strategy_name} strategy\n# {strategy_desc}",
    }


@router.delete("/runs/{run_id}", status_code=status.HTTP_204_NO_CONTENT)
async def stop_run(
    run_id: int,
    current_user: User = Depends(get_current_user),
    session: AsyncSession = Depends(get_session),
) -> None:
    """Stop and delete a trading run."""
    stmt = select(DBTradingRun).where(
        DBTradingRun.id == run_id,
        DBTradingRun.user_id == current_user.id,
    )
    result = await session.execute(stmt)
    run = result.scalar_one_or_none()
    if run is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Запуск не найден.",
        )

    # Try to stop the engine if it's running
    try:
        await scheduler.stop_run(run_id)
    except KeyError:
        pass  # Not active in scheduler, still delete from DB

    # Update status to stopped
    run.status = "stopped"
    run.finished_at = datetime.now(timezone.utc)
    await session.commit()
