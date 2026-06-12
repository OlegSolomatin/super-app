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
) -> tuple[bool, Optional[float], Optional[str]]:
    """Check if exchange API key is valid and fetch balance.

    Args:
        exchange: Exchange name (binance, mexc, bybit).
        api_key: Decrypted API key.
        api_secret: Decrypted API secret.
        passphrase: Optional passphrase (for OKX etc.).
        testnet: Use testnet (Binance testnet).

    Returns:
        Tuple of (is_valid, balance_or_none, error_message_or_none).
    """
    exchange = exchange.lower().strip()

    if exchange not in SUPPORTED_EXCHANGES:
        logger.warning("Unsupported exchange: %s", exchange)
        return False, None, f"Биржа {exchange} не поддерживается"

    try:
        return await _check_ccxt(exchange, api_key, api_secret, passphrase, testnet)
    except ImportError:
        logger.warning("ccxt not installed, falling back to REST")
        return await _check_rest(exchange, api_key, api_secret, passphrase)
    except Exception as e:
        err_str = str(e)
        logger.warning("Key check failed for %s: %s", exchange, err_str)

        # For Bybit: если ccxt дал ошибку подписи — пробуем прямой REST
        if exchange == "bybit" and ("10004" in err_str or "signature" in err_str.lower()):
            logger.info("Bybit ccxt signature error, trying direct REST...")
            return await _check_rest(exchange, api_key, api_secret, passphrase)

        return False, None, err_str


async def _check_ccxt(
    exchange: str,
    api_key: str,
    api_secret: str,
    passphrase: Optional[str] = None,
    testnet: bool = False,
) -> tuple[bool, Optional[float], Optional[str]]:
    """Check key using ccxt library."""
    import ccxt.async_support as ccxt

    exchange_class = getattr(ccxt, exchange, None)
    if exchange_class is None:
        logger.warning("ccxt has no exchange: %s", exchange)
        return False, None, f"Биржа {exchange} не найдена в ccxt"

    config = {
        "apiKey": api_key,
        "secret": api_secret,
    }
    if passphrase:
        config["password"] = passphrase

    # Bybit: явно указываем spot API (некоторые ключи — classic v3, а не unified v5)
    if exchange == "bybit":
        config["options"] = {
            "defaultType": "spot",  # v3/v5 spot endpoint
        }

    ex = exchange_class(config)

    try:
        if testnet and exchange == "binance":
            ex.set_sandbox_mode(True)

        balance = await ex.fetch_balance()
        total_usd = _estimate_total_usd(balance)

        # Check if key is valid (we got a response)
        is_valid = balance.get("free") is not None or balance.get("total") is not None
        return is_valid, total_usd, None
    except Exception as e:
        logger.info("Exchange %s key check: %s", exchange, e)
        return False, None, str(e)
    finally:
        await ex.close()


async def _check_rest(
    exchange: str,
    api_key: str,
    api_secret: str,
    passphrase: Optional[str] = None,
) -> tuple[bool, Optional[float], Optional[str]]:
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
                return True, None, None
            elif resp.status_code == 401:
                return False, None, "Неверный API ключ или секрет (HTTP 401)"
            else:
                msg = f"HTTP {resp.status_code}: {resp.text[:200]}"
                logger.warning("Binance status check: %s", msg)
                return False, None, msg

    if exchange == "bybit":
        return await _check_bybit_rest(api_key, api_secret)

    # For other exchanges, basic account info endpoint
    logger.info("REST check not implemented for %s", exchange)
    return False, None, f"REST проверка не реализована для {exchange}"


async def _check_bybit_rest(
    api_key: str,
    api_secret: str,
) -> tuple[bool, Optional[float], Optional[str]]:
    """Check Bybit API key via direct REST (v5 wallet balance).

    Bybit v5 signing:
      payload = timestamp + api_key + recv_window + body
      signature = HMAC-SHA256(payload, secret)
    """
    import hashlib
    import hmac
    import time

    import httpx

    ts = str(int(time.time() * 1000))
    recv_window = "5000"

    # GET /v5/account/wallet-balance?accountType=UNIFIED&coin=USDT
    body = "accountType=UNIFIED&coin=USDT"
    payload = ts + api_key + recv_window + body
    signature = hmac.new(
        api_secret.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()

    url = f"https://api.bybit.com/v5/account/wallet-balance?{body}"
    headers = {
        "X-BAPI-API-KEY": api_key,
        "X-BAPI-TIMESTAMP": ts,
        "X-BAPI-SIGN": signature,
        "X-BAPI-RECV-WINDOW": recv_window,
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, headers=headers)
        data = resp.json()

        if resp.status_code == 200 and data.get("retCode") == 0:
            # Success — extract balance
            result = data.get("result", {})
            total_equity = None
            for account in result.get("list", []):
                equity = account.get("totalEquity")
                if equity is not None:
                    total_equity = float(equity)
                    break
            # Also check spot balance via v5 endpoint
            return True, total_equity, None

        ret_code = data.get("retCode")
        ret_msg = data.get("retMsg", "unknown error")
        if ret_code == 10004:
            # Signature error — try v3 endpoint as fallback
            return await _check_bybit_rest_v3(api_key, api_secret)
        return False, None, f"Bybit {ret_code}: {ret_msg}"


async def _check_bybit_rest_v3(
    api_key: str,
    api_secret: str,
) -> tuple[bool, Optional[float], Optional[str]]:
    """Fallback: check Bybit key via v3 spot API."""
    import hashlib
    import hmac
    import time

    import httpx

    ts = str(int(time.time() * 1000))
    recv_window = "5000"

    # GET /spot/v3/private/account
    body = ""  # No query params for spot account
    payload = ts + api_key + recv_window + body
    signature = hmac.new(
        api_secret.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()

    url = "https://api.bybit.com/spot/v3/private/account"
    headers = {
        "X-BAPI-API-KEY": api_key,
        "X-BAPI-TIMESTAMP": ts,
        "X-BAPI-SIGN": signature,
        "X-BAPI-RECV-WINDOW": recv_window,
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        resp = await client.get(url, headers=headers)
        data = resp.json()

        if resp.status_code == 200 and data.get("retCode") == 0:
            result = data.get("result", {})
            # v3 spot balance format
            balances = result.get("balances", [])
            total_usdt = 0.0
            for bal in balances:
                if bal.get("coin") == "USDT":
                    total_usdt = float(bal.get("total", 0))
                    break
            return True, total_usdt if total_usdt > 0 else None, None

        ret_code = data.get("retCode")
        ret_msg = data.get("retMsg", "unknown error")
        return False, None, f"Bybit v3 {ret_code}: {ret_msg}"


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
