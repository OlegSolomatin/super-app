"""Shared trading constants — pair list, coin icons.

Centralised here to avoid circular imports between api/v1/trading.py
and services/trading/scheduler.py.
"""

from __future__ import annotations

import asyncio
import logging
import time
from typing import Optional

import aiohttp

logger = logging.getLogger(__name__)

# ── Cache for Binance 24h tickers (price, volume, change) ──
_binance_ticker_cache: dict[str, dict] | None = None
_binance_ticker_cache_time: float = 0.0
BINANCE_VOLUME_CACHE_TTL = 60  # 1 minute


async def fetch_24h_volumes() -> dict[str, float]:
    """Fetch 24h quote volumes (in USDT) for all USDT pairs from Binance."""
    global _binance_ticker_cache, _binance_ticker_cache_time

    now = time.time()
    if _binance_ticker_cache is not None and (now - _binance_ticker_cache_time) < BINANCE_VOLUME_CACHE_TTL:
        return {s: d["volume"] for s, d in _binance_ticker_cache.items()}

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://api.binance.com/api/v3/ticker/24hr",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status != 200:
                    logger.warning("Binance 24hr ticker returned %d", resp.status)
                    return {}

                data = await resp.json()
                tickers: dict[str, dict] = {}
                volumes: dict[str, float] = {}
                for t in data:
                    symbol: str = t.get("symbol", "")
                    if symbol.endswith("USDT") and symbol.isascii():
                        qv = float(t.get("quoteVolume", 0) or 0)
                        volumes[symbol] = qv
                        last_price = float(t.get("lastPrice", 0) or 0)
                        price_change = float(t.get("priceChangePercent", 0) or 0)
                        tickers[symbol] = {
                            "price": float(t.get("lastPrice", 0) or 0),
                            "volume": qv,
                            "change_24h": price_change,
                            "high": float(t.get("highPrice", 0) or 0),
                            "low": float(t.get("lowPrice", 0) or 0),
                        }
                _binance_ticker_cache = tickers
                _binance_ticker_cache_time = now
                logger.info("Fetched 24hr data for %d USDT pairs", len(volumes))
                return volumes

    except Exception as e:
        logger.warning("Failed to fetch 24h volumes: %s", e)
        return {}


async def fetch_24h_tickers() -> dict[str, dict]:
    """Fetch 24hr ticker data (price, volume, change_24h) for all USDT pairs.

    Returns dict mapping symbol -> {price, volume, change_24h}.
    Cached for 60 seconds.
    """
    global _binance_ticker_cache, _binance_ticker_cache_time

    now = time.time()
    if _binance_ticker_cache is not None and (now - _binance_ticker_cache_time) < BINANCE_VOLUME_CACHE_TTL:
        return _binance_ticker_cache

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://api.binance.com/api/v3/ticker/24hr",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status != 200:
                    logger.warning("Binance 24hr ticker returned %d", resp.status)
                    return {}

                data = await resp.json()
                tickers: dict[str, dict] = {}
                for t in data:
                    symbol: str = t.get("symbol", "")
                    if symbol.endswith("USDT") and symbol.isascii():
                        tickers[symbol] = {
                            "price": float(t.get("lastPrice", 0) or 0),
                            "volume": float(t.get("quoteVolume", 0) or 0),
                            "change_24h": float(t.get("priceChangePercent", 0) or 0),
                            "high": float(t.get("highPrice", 0) or 0),
                            "low": float(t.get("lowPrice", 0) or 0),
                        }
                _binance_ticker_cache = tickers
                _binance_ticker_cache_time = now
                logger.info("Fetched 24hr tickers for %d USDT pairs", len(tickers))
                return tickers

    except Exception as e:
        logger.warning("Failed to fetch 24hr tickers: %s", e)
        return {}


# ── Cache for Binance pair list ──
_binance_pairs_cache: list[str] | None = None
_binance_pairs_cache_time: float = 0.0
BINANCE_CACHE_TTL = 300  # 5 minutes


async def fetch_all_usdt_pairs() -> list[str]:
    """Fetch ALL active USDT trading pairs from Binance.

    Results are cached for 5 minutes to avoid hammering the API.
    Falls back to ALL_PAIR_SYMBOLS (hardcoded) on network error.
    """
    global _binance_pairs_cache, _binance_pairs_cache_time

    now = time.time()
    if _binance_pairs_cache is not None and (now - _binance_pairs_cache_time) < BINANCE_CACHE_TTL:
        return _binance_pairs_cache

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://api.binance.com/api/v3/exchangeInfo",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status != 200:
                    logger.warning("Binance API returned %d, using hardcoded pairs", resp.status)
                    return list(ALL_PAIR_SYMBOLS)

                data = await resp.json()
                pairs = [
                    s["symbol"]
                    for s in data.get("symbols", [])
                    if s["symbol"].endswith("USDT") and s["status"] == "TRADING"
                    and s["symbol"].isascii()
                ]
                pairs.sort()
                _binance_pairs_cache = pairs
                _binance_pairs_cache_time = now
                logger.info("Fetched %d USDT pairs from Binance", len(pairs))
                return pairs

    except Exception as e:
        logger.warning("Failed to fetch pairs from Binance: %s — using hardcoded %d pairs", e, len(ALL_PAIR_SYMBOLS))
        return list(ALL_PAIR_SYMBOLS)


# ── Cache for Bybit 24h tickers ──
_bybit_ticker_cache: dict[str, dict] | None = None
_bybit_ticker_cache_time: float = 0.0
BYBIT_CACHE_TTL = 60  # 1 minute
BYBIT_PAIRS_CACHE_TTL = 300  # 5 minutes
_bybit_pairs_cache: list[str] | None = None
_bybit_pairs_cache_time: float = 0.0


async def fetch_bybit_usdt_pairs() -> list[str]:
    """Fetch ALL active USDT trading pairs from Bybit spot market.

    Uses GET /v5/market/instruments-info?category=spot.
    Cached for 5 minutes. Returns sorted list.
    Falls back to empty list on network error.
    """
    global _bybit_pairs_cache, _bybit_pairs_cache_time

    now = time.time()
    if _bybit_pairs_cache is not None and (now - _bybit_pairs_cache_time) < BYBIT_PAIRS_CACHE_TTL:
        return _bybit_pairs_cache

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://api.bybit.com/v5/market/instruments-info?category=spot",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status != 200:
                    logger.warning("Bybit instruments-info returned %d", resp.status)
                    return []

                data = await resp.json()
                if data.get("retCode") != 0:
                    logger.warning("Bybit API error: %s", data.get("retMsg", "unknown"))
                    return []

                pairs = [
                    s["symbol"]
                    for s in data.get("result", {}).get("list", [])
                    if s.get("symbol", "").endswith("USDT")
                    and s.get("status") == "Trading"
                    and s.get("symbol", "").isascii()
                ]
                pairs.sort()
                _bybit_pairs_cache = pairs
                _bybit_pairs_cache_time = now
                logger.info("Fetched %d USDT pairs from Bybit", len(pairs))
                return pairs

    except Exception as e:
        logger.warning("Failed to fetch pairs from Bybit: %s", e)
        return []


async def fetch_bybit_24h_tickers() -> dict[str, dict]:
    """Fetch 24hr ticker data (price, volume, change_24h) for all USDT pairs from Bybit.

    Uses GET /v5/market/tickers?category=spot.
    Returns dict mapping symbol -> {price, volume, change_24h, high, low}.
    Cached for 60 seconds.
    """
    global _bybit_ticker_cache, _bybit_ticker_cache_time

    now = time.time()
    if _bybit_ticker_cache is not None and (now - _bybit_ticker_cache_time) < BYBIT_CACHE_TTL:
        return _bybit_ticker_cache

    try:
        async with aiohttp.ClientSession() as session:
            async with session.get(
                "https://api.bybit.com/v5/market/tickers?category=spot",
                timeout=aiohttp.ClientTimeout(total=15),
            ) as resp:
                if resp.status != 200:
                    logger.warning("Bybit tickers returned %d", resp.status)
                    return {}

                data = await resp.json()
                if data.get("retCode") != 0:
                    logger.warning("Bybit tickers error: %s", data.get("retMsg", "unknown"))
                    return {}

                tickers: dict[str, dict] = {}
                for t in data.get("result", {}).get("list", []):
                    symbol: str = t.get("symbol", "")
                    if symbol.endswith("USDT") and symbol.isascii():
                        tickers[symbol] = {
                            "price": float(t.get("lastPrice", 0) or 0),
                            "volume": float(t.get("turnover24h", 0) or 0),  # Bybit uses turnover24h for quote volume
                            "change_24h": float(t.get("price24hPcnt", 0) or 0) * 100,  # Bybit returns as decimal
                            "high": float(t.get("highPrice24h", 0) or 0),
                            "low": float(t.get("lowPrice24h", 0) or 0),
                        }

                _bybit_ticker_cache = tickers
                _bybit_ticker_cache_time = now
                logger.info("Fetched 24hr tickers for %d USDT pairs from Bybit", len(tickers))
                return tickers

    except Exception as e:
        logger.warning("Failed to fetch Bybit 24hr tickers: %s", e)
        return {}


async def fetch_bybit_ticker(symbol: str) -> dict | None:
    """Fetch 24hr ticker data for a SINGLE Bybit pair.

    Uses GET /v5/market/tickers?category=spot&symbol={symbol}.
    Returns dict {price, volume, high, low, change_24h} or None on failure.
    """
    try:
        url = f"https://api.bybit.com/v5/market/tickers?category=spot&symbol={symbol}"
        async with aiohttp.ClientSession() as session:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=10)) as resp:
                if resp.status != 200:
                    return None
                data = await resp.json()
                if data.get("retCode") != 0:
                    return None
                items = data.get("result", {}).get("list", [])
                if not items:
                    return None
                t = items[0]
                return {
                    "price": float(t.get("lastPrice", 0) or 0),
                    "volume": float(t.get("turnover24h", 0) or 0),
                    "change_24h": float(t.get("price24hPcnt", 0) or 0) * 100,
                    "high": float(t.get("highPrice24h", 0) or 0),
                    "low": float(t.get("lowPrice24h", 0) or 0),
                }
    except Exception as e:
        logger.warning("Failed to fetch Bybit ticker for %s: %s", symbol, e)
        return None


# ── Coin icon names (for crypto logos CDN) ──
COIN_ICON_NAMES: dict[str, str] = {
    "BTC": "bitcoin-btc",
    "ETH": "ethereum-eth",
    "BNB": "binance-coin-bnb",
    "SOL": "solana-sol",
    "XRP": "xrp-xrp",
    "ADA": "cardano-ada",
    "DOGE": "dogecoin-doge",
    "AVAX": "avalanche-avax",
    "DOT": "polkadot-dot",
    "MATIC": "polygon-matic",
    "LTC": "litecoin-ltc",
    "LINK": "chainlink-link",
    "UNI": "uniswap-uni",
    "ATOM": "cosmos-atom",
    "ETC": "ethereum-classic-etc",
    "FIL": "filecoin-fil",
    "TRX": "tron-trx",
    "XLM": "stellar-xlm",
    "VET": "vechain-vet",
    "ALGO": "algorand-algo",
    "NEAR": "near-protocol-near",
    "FTM": "fantom-ftm",
    "SAND": "the-sandbox-sand",
    "MANA": "decentraland-mana",
    "AXS": "axie-infinity-axs",
    "APE": "apecoin-ape",
    "SHIB": "shiba-inu-shib",
    "CRO": "crypto-com-cro",
    "EOS": "eos-eos",
    "ICX": "icon-icx",
    "ZEC": "zcash-zec",
    "XMR": "monero-xmr",
    "DASH": "dash-dash",
    "ZIL": "zilliqa-zil",
    "KSM": "kusama-ksm",
    "COMP": "compound-comp",
    "YFI": "yearn-finance-yfi",
    "AAVE": "aave-aave",
    "MKR": "maker-mkr",
    "BAT": "basic-attention-token-bat",
    "ENJ": "enjin-coin-enj",
    "CHZ": "chiliz-chz",
    "ONE": "harmony-one",
    "ANKR": "ankr-ankr",
    "IOST": "iost-iost",
    "WAVES": "waves-waves",
    "ONT": "ontology-ont",
    "IOTA": "miota-iota",
    "NANO": "nano-nano",
    "LSK": "lisk-lsk",
}

# ── All available USDT trading pairs ──
ALL_PAIR_SYMBOLS: list[str] = [
    "BTCUSDT", "ETHUSDT", "BNBUSDT", "SOLUSDT", "XRPUSDT",
    "ADAUSDT", "DOGEUSDT", "AVAXUSDT", "DOTUSDT", "MATICUSDT",
    "LTCUSDT", "LINKUSDT", "UNIUSDT", "ATOMUSDT", "ETCUSDT",
    "FILUSDT", "TRXUSDT", "XLMUSDT", "VETUSDT", "ALGOUSDT",
    "NEARUSDT", "FTMUSDT", "SANDUSDT", "MANAUSDT", "AXSUSDT",
    "APEUSDT", "SHIBUSDT", "CROUSDT", "EOSUSDT", "ICXUSDT",
    "ZECUSDT", "XMRUSDT", "DASHUSDT", "ZILUSDT", "KSMUSDT",
    "COMPUSDT", "YFIUSDT", "AAVEUSDT", "MKRUSDT", "BATUSDT",
    "ENJUSDT", "CHZUSDT", "ONEUSDT", "ANKRUSDT", "IOSTUSDT",
    "WAVESUSDT", "ONTUSDT", "IOTAUSDT", "NANOUSDT", "LSKUSDT",
]


def get_coin_icon_url(base: str) -> Optional[str]:
    """Return crypto logos CDN URL for a coin symbol, or None."""
    name = COIN_ICON_NAMES.get(base)
    if name:
        return f"https://cryptologos.cc/logos/{name}-logo.png?v=040"
    return None
