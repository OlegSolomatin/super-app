"""Telegram channel parser for trading signal screeners.

Parses @brushscreener (ёршики) and @stairscreener (лесенки) channels
from the Telegram Web preview (t.me/s/...).

Returns structured TradingSignal objects ready for classification.
"""

from __future__ import annotations

import logging
import re
from dataclasses import dataclass, field
from typing import Optional

import httpx

logger = logging.getLogger(__name__)

TELEGRAM_PREVIEW_URL = "https://t.me/s/"

CHANNELS = {
    "brushscreener": TELEGRAM_PREVIEW_URL + "brushscreener",
    "stairscreener": TELEGRAM_PREVIEW_URL + "stairscreener",
}


@dataclass
class RawSignal:
    """Raw parsed signal data from a Telegram post."""

    channel: str
    exchange: str
    pair: str
    price_range: Optional[float] = None
    vol_60m: Optional[float] = None
    vol_10m: Optional[float] = None
    slope: Optional[float] = None
    top_ratio: Optional[float] = None
    bot_ratio: Optional[float] = None
    raw_text: str = ""


def _parse_stair_signal(text: str) -> Optional[RawSignal]:
    """Parse a stair screener post.

    Format:
    Mexc - FuturesLIGHT/USDT
    Price range: 0.6 %
    Last 60 mins vol: 11878 $
    Last 10 mins vol: 745 $
    Slope: 4.03
    """
    try:
        # Exchange and pair
        exchange_pair = re.search(r"^(.+?)\n", text)
        if not exchange_pair:
            # Try first line from text
            lines = text.strip().split("\n")
            first = lines[0] if lines else ""
            # Extract exchange from first meaningful part
            exchange_match = re.match(r"([A-Za-z\s-]+)", first)
            exchange = exchange_match.group(1).strip() if exchange_match else "Mexc"
            # Extract pair
            pair_match = re.search(r"([A-Z0-9]{2,10})/USD", first) or re.search(
                r"([A-Z0-9]{2,10})USDT", first
            )
            pair = pair_match.group(1) + "USDT" if pair_match else ""
        else:
            first_line = exchange_pair.group(1)
            exchange_match = re.match(r"([A-Za-z\s-]+)", first_line)
            exchange = exchange_match.group(1).strip() if exchange_match else "Mexc"
            pair_match = re.search(r"([A-Z0-9]{2,10})/USD", first_line) or re.search(
                r"([A-Z0-9]{2,10})USDT", first_line
            )
            pair = pair_match.group(1) + "USDT" if pair_match else ""

        if not pair:
            logger.warning("Could not extract pair from stair signal: %s", text[:50])
            return None

        # Price range
        range_m = re.search(r"Price range:\s*([\d.]+)\s*%", text)
        price_range = float(range_m.group(1)) if range_m else None

        # Volumes
        vol60_m = re.search(r"Last 60 mins vol:\s*([\d.]+)\s*\$", text)
        vol10_m = re.search(r"Last 10 mins vol:\s*([\d.]+)\s*\$", text)
        vol_60m = float(vol60_m.group(1)) if vol60_m else None
        vol_10m = float(vol10_m.group(1)) if vol10_m else None

        # Slope
        slope_m = re.search(r"Slope:\s*([\d.]+)", text)
        slope = float(slope_m.group(1)) if slope_m else None

        return RawSignal(
            channel="stairscreener",
            exchange=exchange.strip(),
            pair=pair.upper(),
            price_range=price_range,
            vol_60m=vol_60m,
            vol_10m=vol_10m,
            slope=slope,
            raw_text=text,
        )
    except Exception as e:
        logger.warning("Failed to parse stair signal: %s", e)
        return None


def _parse_brush_signal(text: str) -> Optional[RawSignal]:
    """Parse a brush screener post.

    Format:
    MexcPYPLON/USDT
    Price range: 1.0 %
    Last 60 mins vol: 8162 $
    Last 10 mins vol: 423 $
    Top/Bot touch ratio: 0.08 / 0.09
    """
    try:
        # Exchange and pair from first line
        lines = text.strip().split("\n")
        first = lines[0] if lines else ""

        # Parse exchange and pair from combined first token
        exchange = "Mexc"
        pair = ""

        # Try to find pair/USD or pairUSDT
        pair_match = re.search(r"([A-Z0-9]{2,20})/USD", first) or re.search(
            r"([A-Z0-9]{2,20})USDT", first
        )
        if pair_match:
            pair = pair_match.group(1) + "USDT"
            # Exchange is everything before the pair token
            before = first[: pair_match.start()]
            if before.strip():
                exchange = before.strip().rstrip("- ")

        if not pair:
            logger.warning("Could not extract pair from brush signal: %s", text[:50])
            return None

        # Price range
        range_m = re.search(r"Price range:\s*([\d.]+)\s*%", text)
        price_range = float(range_m.group(1)) if range_m else None

        # Volumes
        vol60_m = re.search(r"Last 60 mins vol:\s*([\d.]+)\s*\$", text)
        vol10_m = re.search(r"Last 10 mins vol:\s*([\d.]+)\s*\$", text)
        vol_60m = float(vol60_m.group(1)) if vol60_m else None
        vol_10m = float(vol10_m.group(1)) if vol10_m else None

        # Top/Bot ratio
        ratio_m = re.search(r"Top/Bot touch ratio:\s*([\d.]+)\s*/\s*([\d.]+)", text)
        top_ratio = float(ratio_m.group(1)) if ratio_m else None
        bot_ratio = float(ratio_m.group(2)) if ratio_m else None

        return RawSignal(
            channel="brushscreener",
            exchange=exchange.strip(),
            pair=pair.upper(),
            price_range=price_range,
            vol_60m=vol_60m,
            vol_10m=vol_10m,
            top_ratio=top_ratio,
            bot_ratio=bot_ratio,
            raw_text=text,
        )
    except Exception as e:
        logger.warning("Failed to parse brush signal: %s", e)
        return None


def _extract_messages(html: str) -> list[str]:
    """Extract message texts from Telegram Web preview HTML."""
    import html as html_mod

    # Find all message text blocks
    texts = re.findall(
        r'<div class="tgme_widget_message_text[^"]*"[^>]*>(.*?)</div>',
        html,
        re.DOTALL,
    )
    result = []
    for t in texts:
        # Strip HTML tags
        t = re.sub(r"<[^>]+>", "", t)
        t = html_mod.unescape(t)
        t = t.strip()
        if t:
            result.append(t)
    return result


async def parse_channel(channel_name: str) -> list[RawSignal]:
    """Fetch and parse the latest signals from a Telegram channel.

    Args:
        channel_name: 'brushscreener' or 'stairscreener'

    Returns:
        List of RawSignal objects (up to 10 most recent)
    """
    url = CHANNELS.get(channel_name)
    if not url:
        logger.warning("Unknown channel: %s", channel_name)
        return []

    try:
        async with httpx.AsyncClient(timeout=15) as client:
            resp = await client.get(url)
            resp.raise_for_status()
            html = resp.text
    except Exception as e:
        logger.error("Failed to fetch %s: %s", url, e)
        return []

    messages = _extract_messages(html)
    parser = _parse_brush_signal if channel_name == "brushscreener" else _parse_stair_signal

    signals: list[RawSignal] = []
    seen_pairs: set[str] = set()

    for msg in messages:
        parsed = parser(msg)
        if parsed and parsed.pair not in seen_pairs:
            signals.append(parsed)
            seen_pairs.add(parsed.pair)
            if len(signals) >= 10:
                break

    return signals


async def parse_all_channels() -> list[RawSignal]:
    """Parse all known screener channels."""
    all_signals: list[RawSignal] = []
    for channel in CHANNELS:
        try:
            signals = await parse_channel(channel)
            all_signals.extend(signals)
        except Exception as e:
            logger.error("Error parsing channel %s: %s", channel, e)
    return all_signals
