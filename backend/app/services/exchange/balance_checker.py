"""Service for checking exchange API key validity and fetching balances.

Supports any exchange available in ccxt (100+ exchanges).
Balance checking via ccxt.fetch_balance().
Bybit uses direct REST due to unified account issues.
"""

from __future__ import annotations

import asyncio
import logging
from typing import Optional

logger = logging.getLogger(__name__)


def get_supported_exchanges() -> set[str]:
    """Get all exchanges supported by ccxt for key checking.

    Returns set of exchange names that can be used for API key management.
    """
    try:
        import ccxt.async_support as ccxt
        return set(ccxt.exchanges)
    except ImportError:
        return {"binance", "mexc", "bybit"}  # fallback


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

    supported = get_supported_exchanges()

    if exchange not in supported:
        logger.warning("Unsupported exchange: %s", exchange)
        return False, None, f"Биржа {exchange} не поддерживается. ccxt поддерживает: {', '.join(sorted(supported)[:10])}..."

    # Bybit: сразу прямой REST (ccxt неправильно подписывает для классических ключей)
    if exchange == "bybit":
        return await _check_bybit_rest(api_key, api_secret)

    try:
        # Wrap in a timeout to prevent long hangs
        return await asyncio.wait_for(
            _check_ccxt(exchange, api_key, api_secret, passphrase, testnet),
            timeout=20.0,
        )
    except asyncio.TimeoutError:
        logger.warning("Key check timed out for %s (>20s)", exchange)
        return False, None, "Таймаут соединения с биржей (>20 секунд). Попробуйте позже."
    except ImportError:
        logger.warning("ccxt not installed, falling back to REST")
        return await asyncio.wait_for(
            _check_rest(exchange, api_key, api_secret, passphrase),
            timeout=15.0,
        )
    except Exception as e:
        err_str = str(e)
        logger.warning("Key check failed for %s: %s", exchange, err_str)
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

    # Bybit: явно отключаем unified account (классические ключи не работают с v5)
    if exchange == "bybit":
        config["options"] = {
            "defaultType": "spot",
            "enableUnifiedAccount": False,
            "enableUnifiedMargin": False,
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
    """Check Bybit API key via direct REST.

    Strategy:
      1. GET /v5/user/query-api — проверка валидности ключа (не требует прав)
      2. Если ключ валиден → GET /v5/account/wallet-balance — баланс
      3. Если v5 не работает → v3 spot
    """
    import hashlib
    import hmac
    import time

    import httpx

    ts = str(int(time.time() * 1000))
    recv_window = "5000"

    # ── 1. Проверка валидности ключа через /v5/user/query-api ──────────────
    #      (без query-параметров — чистый GET, не требует прав)
    #      payload: timestamp + api_key + recv_window (body пустой для GET без params)
    body = ""
    payload = ts + api_key + recv_window + body
    signature = hmac.new(
        api_secret.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()

    url = "https://api.bybit.com/v5/user/query-api"
    headers = {
        "X-BAPI-API-KEY": api_key,
        "X-BAPI-TIMESTAMP": ts,
        "X-BAPI-SIGN": signature,
        "X-BAPI-RECV-WINDOW": recv_window,
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v5/query-api] ts={ts}, api_key={api_key[:8]}..., rw={recv_window}\n")
            f.write(f"[BYBIT v5/query-api] payload='{payload}', sig={signature[:40]}...\n")

        resp = await client.get(url, headers=headers)
        resp_text = resp.text[:500]
        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v5/query-api] HTTP {resp.status_code}, body={resp_text}\n")

        try:
            data = resp.json()
        except Exception:
            return False, None, f"Bybit query-api: HTTP {resp.status_code}, не-JSON: {resp.text[:300]}"

        ret_code = data.get("retCode")
        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v5/query-api] retCode={ret_code}\n")
        if data.get("retCode") != 0:
            ret_code = data.get("retCode")
            ret_msg = data.get("retMsg", "unknown")

            # Если v5 не работает — пробуем v3 как запасной вариант
            if ret_code == 10004:
                v3_result = await _check_bybit_rest_v3(api_key, api_secret)
                # Если v3 тоже дал discontinued — делаем понятную ошибку
                if not v3_result[0] and "V3 API" in (v3_result[2] or ""):
                    return False, None, "❌ Bybit V3 API отключён (с 31.08.2024). Ключ несовместим. Создайте новый V5 ключ в Bybit"
                return v3_result

            return False, None, f"Bybit {ret_code}: {ret_msg}"

        # ── 2. Успех — запрашиваем баланс через /v5/account/wallet-balance ──
        ts2 = str(int(time.time() * 1000))
        body2 = "accountType=UNIFIED&coin=USDT"
        payload2 = ts2 + api_key + recv_window + body2
        sig2 = hmac.new(
            api_secret.encode(), payload2.encode(), hashlib.sha256
        ).hexdigest()

        url2 = f"https://api.bybit.com/v5/account/wallet-balance?{body2}"
        headers2 = {
            "X-BAPI-API-KEY": api_key,
            "X-BAPI-TIMESTAMP": ts2,
            "X-BAPI-SIGN": sig2,
            "X-BAPI-RECV-WINDOW": recv_window,
        }

        resp2 = await client.get(url2, headers=headers2)
        try:
            data2 = resp2.json()
        except Exception:
            # Key valid, but balance unavailable
            return True, None, None
        
        if data2.get("retCode") == 0:
            total_equity = None
            for account in data2.get("result", {}).get("list", []):
                equity = account.get("totalEquity")
                if equity is not None:
                    total_equity = float(equity)
                    break
            return True, total_equity, None
        
        # Key valid, balance endpoint failed
        return True, None, None


async def _check_bybit_rest_v3(
    api_key: str,
    api_secret: str,
) -> tuple[bool, Optional[float], Optional[str]]:
    """Fallback: check Bybit key via v3 spot API (без recv_window в подписи для v3)."""
    import hashlib
    import hmac
    import time

    import httpx

    ts = str(int(time.time() * 1000))

    # v3 spot: payload = timestamp + api_key + query_string (без recv_window)
    body = ""  # No query params
    payload = ts + api_key + body
    signature = hmac.new(
        api_secret.encode(), payload.encode(), hashlib.sha256
    ).hexdigest()

    url = "https://api.bybit.com/spot/v3/private/account"
    headers = {
        "X-BAPI-API-KEY": api_key,
        "X-BAPI-TIMESTAMP": ts,
        "X-BAPI-SIGN": signature,
    }

    async with httpx.AsyncClient(timeout=10.0) as client:
        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v3] GET {url} ts={ts} sig={signature[:40]}...\n")
        resp = await client.get(url, headers=headers)
        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v3] response: HTTP {resp.status_code}, body={resp.text[:400]}\n")
        try:
            data = resp.json()
        except Exception:
            text = resp.text[:300]
            # Detect "v3 discontinued" message from Bybit
            if "discontinued" in text.lower() or "v3" in text.lower():
                return False, None, "❌ Bybit отключил V3 API с 31.08.2024. Создайте новый V5 ключ в Bybit → API Management"
            return False, None, f"Bybit v3: HTTP {resp.status_code}, не-JSON ответ: {text}"

        with open("/tmp/bybit_debug.log", "a") as f:
            f.write(f"[BYBIT v3] parsed: retCode={data.get('retCode')}\n")

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

    Only counts USDT and USD-pegged stablecoins (USDC, BUSD, DAI, TUSD, FDUSD).
    Non-stable assets (BTC, ETH, etc.) are NOT converted — their raw amounts
    would give a wrong USD estimate without ticker prices.
    """
    STABLECOINS = {"USDT", "USDC", "BUSD", "DAI", "TUSD", "FDUSD", "USDD"}
    try:
        total = balance.get("total", {})
        if not isinstance(total, dict):
            return None

        usd_value = 0.0
        for currency, amount in total.items():
            if not isinstance(amount, (int, float)) or amount <= 0:
                continue
            if currency.upper() in STABLECOINS:
                usd_value += float(amount)

        return round(usd_value, 2) if usd_value > 0 else None
    except Exception:
        return None
