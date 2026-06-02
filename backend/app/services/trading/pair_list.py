"""Shared trading constants — pair list, coin icons.

Centralised here to avoid circular imports between api/v1/trading.py
and services/trading/scheduler.py.
"""

from typing import Optional

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
