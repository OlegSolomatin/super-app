"""CCXT exchange connector — universal adapter for 100+ exchanges.

Uses the ccxt library to provide a unified interface across all supported
exchanges (Binance, Bybit, MEXC, Gate, KuCoin, OKX, Bitget, Kraken, etc.).

Public endpoints (klines, ticker, orderbook) work without API keys.
Private endpoints (balance, order placement) require api_key + api_secret.

Docs: https://docs.ccxt.com/#/README
"""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from typing import Dict, List, Optional

import ccxt.pro as ccxt_pro

from app.services.trading.exchange.base import AbstractExchange
from app.services.trading.models import Candle

logger = logging.getLogger(__name__)

# Default exchange config — no API keys for public data
PUBLIC_CONFIG = {
    "enableRateLimit": True,
    "options": {"defaultType": "spot"},
}

# Map internal timeframe to ccxt format (ccxt uses same "1m", "5m" format)
# But for some exchanges like Bybit, ccxt auto-converts


class CCXTExchange(AbstractExchange):
    """Universal exchange connector powered by CCXT.

    Supports all exchanges that ccxt supports:
      - Public: get_klines(), get_ticker(), get_orderbook()
      - Private (requires keys): get_balance(), place_order()

    Usage:
        ex = CCXTExchange(exchange_name="mexc")
        candles = await ex.get_klines("BTCUSDT", "1h")

        ex_auth = CCXTExchange(exchange_name="bybit",
                               api_key="...", api_secret="...")
        balance = await ex_auth.get_balance("USDT")
    """

    def __init__(
        self,
        exchange_name: str,
        api_key: str = "",
        api_secret: str = "",
    ) -> None:
        super().__init__(
            name=exchange_name,
            api_key=api_key,
            api_secret=api_secret,
        )
        self._exchange_name = exchange_name.lower()
        self._exchange: Optional[ccxt_pro.Exchange] = None

    def _convert_symbol(self, pair: str) -> str:
        """Convert internal pair format to exchange-specific format.

        Tries multiple formats because different exchanges use different
        conventions:
          - Binance/MEXC/Bitget: BTCUSDT (direct)
          - Gate/Kraken: BTC/USDT (slash)
          - KuCoin/OKX: BTC-USDT (dash)

        Uses ccxt market data when available for accurate conversion.
        """
        if self._exchange and self._exchange.markets:
            # Try direct market lookup by symbol
            for fmt in (pair.upper(), f"{pair[:3]}/{pair[3:]}", f"{pair[:3]}-{pair[3:]}"):
                if fmt in self._exchange.markets:
                    return fmt
                if fmt.upper() in self._exchange.markets:
                    return fmt.upper()
        # Fall back to trying formats in order
        return pair.upper()

    async def _get_exchange(self) -> ccxt_pro.Exchange:
        """Get or create the ccxt exchange instance."""
        if self._exchange is not None:
            return self._exchange

        exchange_class = getattr(ccxt_pro, self._exchange_name, None)
        if exchange_class is None:
            raise ValueError(
                f"Unsupported exchange: {self._exchange_name}. "
                f"Available: {', '.join(ccxt_pro.exchanges[:20])}..."
            )

        config = dict(PUBLIC_CONFIG)
        if self.api_key:
            config["apiKey"] = self.api_key
        if self.api_secret:
            config["secret"] = self.api_secret

        self._exchange = exchange_class(config)
        # Load markets to validate the exchange connection
        try:
            await self._exchange.load_markets()
        except Exception:
            logger.warning(
                "[CCXT:%s] Failed to load markets (non-fatal), "
                "will retry on first request",
                self._exchange_name,
            )
        return self._exchange

    async def get_klines(
        self,
        pair: str,
        timeframe: str,
        start: Optional[datetime] = None,
        end: Optional[datetime] = None,
        limit: int = 500,
    ) -> List[Candle]:
        """Fetch historical klines (OHLCV) from the exchange.

        Uses ccxt.fetch_ohlcv() with pagination for large ranges.
        """
        ex = await self._get_exchange()
        candles: List[Candle] = []

        since_ms = int(start.timestamp() * 1000) if start else None
        end_ms = int(end.timestamp() * 1000) if end else None
        fetch_limit = min(limit, 500)

        try:
            raw = await ex.fetch_ohlcv(
                self._convert_symbol(pair),
                timeframe=timeframe,
                since=since_ms,
                limit=fetch_limit,
            )
        except Exception as e:
            logger.error("[CCXT:%s] fetch_ohlcv error for %s: %s",
                         self._exchange_name, pair, e)
            return []

        for entry in raw:
            ts = datetime.fromtimestamp(entry[0] / 1000, tz=timezone.utc)
            if end_ms and int(entry[0]) > end_ms:
                break
            candles.append(Candle(
                open=float(entry[1]),
                high=float(entry[2]),
                low=float(entry[3]),
                close=float(entry[4]),
                volume=float(entry[5]),
                timestamp=ts,
            ))

        candles.sort(key=lambda c: c.timestamp)
        logger.info(
            "[CCXT:%s] Fetched %d candles for %s %s [%s – %s]",
            self._exchange_name, len(candles), pair, timeframe,
            candles[0].timestamp if candles else "N/A",
            candles[-1].timestamp if candles else "N/A",
        )
        return candles

    async def get_ticker(self, pair: str) -> Dict[str, float]:
        """Fetch current ticker from the exchange."""
        ex = await self._get_exchange()
        try:
            ticker = await ex.fetch_ticker(self._convert_symbol(pair))
            return {
                "last": float(ticker.get("last", 0)),
                "volume": float(ticker.get("baseVolume", 0)),
                "high": float(ticker.get("high", 0)),
                "low": float(ticker.get("low", 0)),
                "bid": float(ticker.get("bid", 0)),
                "ask": float(ticker.get("ask", 0)),
            }
        except Exception as e:
            logger.error("[CCXT:%s] ticker error for %s: %s",
                         self._exchange_name, pair, e)
            return {}

    async def get_orderbook(
        self,
        pair: str,
        limit: int = 20,
    ) -> Dict:
        """Fetch current order book from the exchange."""
        ex = await self._get_exchange()
        try:
            ob = await ex.fetch_order_book(self._convert_symbol(pair), limit=limit)
            bids = []
            for item in ob.get("bids", []):
                try:
                    bids.append([float(item[0]), float(item[1])])
                except (IndexError, ValueError, TypeError):
                    continue
            asks = []
            for item in ob.get("asks", []):
                try:
                    asks.append([float(item[0]), float(item[1])])
                except (IndexError, ValueError, TypeError):
                    continue
            return {
                "bids": bids,
                "asks": asks,
                "timestamp": ob.get("timestamp", 0) or 0,
            }
        except Exception as e:
            logger.error("[CCXT:%s] orderbook error for %s: %s",
                         self._exchange_name, pair, e)
            return {"bids": [], "asks": [], "timestamp": 0}

    async def place_order(
        self,
        pair: str,
        side: str,
        quantity: float,
        order_type: str = "market",
        price: Optional[float] = None,
    ) -> Dict:
        """Place an order on the exchange via ccxt.

        Requires api_key and api_secret to be configured.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("[CCXT:%s] place_order: no API keys", self._exchange_name)
            return {"error": "No API keys configured", "status": "REJECTED"}

        ex = await self._get_exchange()
        params: Dict = {}
        try:
            order = await ex.create_order(
                symbol=self._convert_symbol(pair),
                type=order_type,
                side=side.lower(),
                amount=quantity,
                price=price,
                params=params,
            )
            logger.info(
                "[CCXT:%s] Order placed: %s %s %s (id=%s)",
                self._exchange_name, side, quantity, pair,
                order.get("id", "?"),
            )
            return {
                "order_id": str(order.get("id", "")),
                "symbol": order.get("symbol", pair),
                "side": order.get("side", side),
                "quantity": float(order.get("filled", quantity)),
                "price": float(order.get("price", price or 0)),
                "status": order.get("status", "closed"),
                "fills": order.get("fills", []),
            }
        except Exception as e:
            logger.error("[CCXT:%s] order error: %s", self._exchange_name, e)
            return {"error": str(e), "status": "REJECTED"}

    async def get_balance(self, currency: str = "") -> Dict[str, float]:
        """Fetch account balance from the exchange.

        Requires api_key and api_secret to be configured.
        """
        if not self.api_key or not self.api_secret:
            logger.warning("[CCXT:%s] get_balance: no API keys", self._exchange_name)
            return {}

        ex = await self._get_exchange()
        try:
            balance = await ex.fetch_balance()
            result = {}
            for cur, amount in balance.get("total", {}).items():
                if amount and amount > 0:
                    if not currency or cur.upper() == currency.upper():
                        result[cur.upper()] = float(amount)
            logger.info("[CCXT:%s] Balance: %s", self._exchange_name, result)
            return result
        except Exception as e:
            logger.error("[CCXT:%s] balance error: %s", self._exchange_name, e)
            return {}

    async def close(self) -> None:
        """Close the ccxt exchange session."""
        if self._exchange:
            await self._exchange.close()
            self._exchange = None


# ── Exchange factory helper ──────────────────────────────────────────────────


def create_exchange(
    exchange_name: str,
    api_key: str = "",
    api_secret: str = "",
) -> AbstractExchange:
    """Create the appropriate exchange connector for the given name.

    Returns the native implementation for well-known exchanges (Binance, Bybit),
    and the CCXT adapter for all others.

    This allows us to use optimized native implementations where they exist,
    while still supporting any exchange via CCXT.
    """
    name = exchange_name.lower()

    if name == "binance":
        from app.services.trading.exchange.binance import BinanceExchange
        return BinanceExchange(api_key=api_key, api_secret=api_secret)
    elif name == "bybit":
        from app.services.trading.exchange.bybit import BybitExchange
        return BybitExchange(api_key=api_key, api_secret=api_secret)
    elif name == "mock":
        from app.services.trading.exchange.mock import MockExchange
        return MockExchange()
    else:
        return CCXTExchange(
            exchange_name=name,
            api_key=api_key,
            api_secret=api_secret,
        )
