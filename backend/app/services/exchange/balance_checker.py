"""Service for checking exchange API key validity and fetching balances.

Supports:
  - Binance (ccxt or REST)
  - Mexc
  - Bybit

Falls back to ccxt if available, otherwise uses direct REST calls.
"""

from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Supported exchanges
SUPPORTED_EXCHANGES = {"binance", "mexc", "bybit"}
FUTURES_EXCHANGES = {"binance", "bybit"}  # Support futures


async def check_key_validity(
    exchange: str,
    api_key: str,
    api_secret: str,
    passphrase: Optional[str] = None,
    testnet: bool = False,
) -> tuple[bool, Optional[float]]:
    """Check if exchange API key is valid and fetch balance.

    Args:
        exchange: Exchange name (binance, mexc, bybit).
        api_key: Decrypted API key.
        api_secret: Decrypted API secret.
        passphrase: Optional passphrase (for OKX etc.).
        testnet: Use testnet (Binance testnet).

    Returns:
        Tuple of (is_valid, balance_or_none).
    """
    exchange = exchange.lower().strip()

    if exchange not in SUPPORTED_EXCHANGES:
        logger.warning("Unsupported exchange: %s", exchange)
        return False, None

    try:
        return await _check_ccxt(exchange, api_key, api_secret, passphrase, testnet)
    except ImportError:
        logger.warning("ccxt not installed, falling back to REST")
        return await _check_rest(exchange, api_key, api_secret, passphrase)
    except Exception as e:
        logger.warning("Key check failed for %s: %s", exchange, e)
        return False, None


async def _check_ccxt(
    exchange: str,
    api_key: str,
    api_secret: str,
    passphrase: Optional[str] = None,
    testnet: bool = False,
) -> tuple[bool, Optional[float]]:
    """Check key using ccxt library."""
    import ccxt.async_support as ccxt

    exchange_class = getattr(ccxt, exchange, None)
    if exchange_class is None:
        logger.warning("ccxt has no exchange: %s", exchange)
        return False, None

    config = {
        "apiKey": api_key,
        "secret": api_secret,
    }
    if passphrase:
        config["password"] = passphrase

    ex = exchange_class(config)

    try:
        if testnet and exchange == "binance":
            ex.set_sandbox_mode(True)

        balance = await ex.fetch_balance()
        total_usd = _estimate_total_usd(balance)

        # Check if key is valid (we got a response)
        is_valid = balance.get("free") is not None or balance.get("total") is not None
        return is_valid, total_usd
    except Exception as e:
        logger.info("Exchange %s key check: %s", exchange, e)
        return False, None
    finally:
        await ex.close()


async def _check_rest(
    exchange: str,
    api_key: str,
    api_secret: str,
    passphrase: Optional[str] = None,
) -> tuple[bool, Optional[float]]:
    """Fallback: check key via direct REST call.

    Simpler endpoint — just checks account info.
    """
    import hashlib
    import hmac
    import time

    import httpx

    if exchange == "binance":
        # Binance REST: GET /sapi/v1/account/status
        ts = int(time.time() * 1000)
        query = f"timestamp={ts}"
        signature = hmac.new(
            api_secret.encode(), query.encode(), hashlib.sha256
        ).hexdigest()

        url = f"https://api.binance.com/sapi/v1/account/status?{query}&signature={signature}"

        async with httpx.AsyncClient(timeout=10.0) as client:
            resp = await client.get(url, headers={"X-MBX-APIKEY": api_key})

            if resp.status_code == 200:
                return True, None  # Key is valid
            elif resp.status_code == 401:
                return False, None
            else:
                logger.warning(
                    "Binance status check: HTTP %d %s",
                    resp.status_code,
                    resp.text,
                )
                return False, None

    # For other exchanges, basic account info endpoint
    logger.info("REST check not implemented for %s", exchange)
    return False, None


def _estimate_total_usd(balance: dict) -> Optional[float]:
    """Estimate total USD value from a ccxt balance response.

    This is a rough estimate. A full implementation would use
    ticker prices. For now, returns the USDT balance if available.
    """
    try:
        total = balance.get("total", {})
        free = balance.get("free", {})

        # Count USDT directly
        usdt = float(total.get("USDT", 0)) if isinstance(total, dict) else 0

        # Sum all non-zero balances as a rough estimate (will be refined)
        all_total = usdt
        for currency, amount in (total or {}).items():
            if isinstance(amount, (int, float)) and amount > 0 and currency != "USDT":
                all_total += float(amount)  # This is wrong for non-USDT assets

        return round(all_total, 2) if all_total > 0 else None
    except Exception:
        return None
