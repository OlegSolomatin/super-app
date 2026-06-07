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
