"""Strategy configuration for signal classification — maps channels to available strategies.

Each channel (brushscreener, stairscreener) has exactly 2 strategy options.
LLM receives these 2 options and picks one based on signal characteristics.
"""
from __future__ import annotations

from typing import Any


# ── Channel → strategy options ─────────────────────────────────────────────

CHANNEL_STRATEGIES: dict[str, dict[str, Any]] = {
    "brushscreener": {
        "strategies": [
            {
                "id": "ers_scalping",
                "engine": "ob",
                "label": "Ёршик",
                "description": "Для: равные касания top/bot, малый range <3%",
                "wizard_params": {
                    "stoploss": {"min": -3.0, "max": -0.5, "default": -1.5},
                    "trailing_stop": {"min": 0.1, "max": 1.0, "default": 0.3},
                    "conf_ticks": {"min": 1, "max": 5, "default": 1},
                    "max_spread": {"min": 0.05, "max": 0.5, "default": 0.1},
                    "max_hold": {"min": 30, "max": 300, "default": 120},
                    "cooldown": {"min": 30, "max": 300, "default": 30},
                    "ers_min_imbalance": {"min": 0.50, "max": 0.80, "default": 0.52},
                    "balance": {"min": 5, "max": 100, "default": 10},
                    "auto_stop": {"options": [1, 2, 4, 6], "default": 1},
                },
            },
            {
                "id": "imbalance_scalping",
                "engine": "ob",
                "label": "Дисбаланс",
                "description": "Для: одна сторона доминирует >1.5x, накопление/распределение",
                "wizard_params": {
                    "stoploss": {"min": -3.0, "max": -1.0, "default": -2.0},
                    "max_hold": {"min": 60, "max": 300, "default": 120},
                    "imbalance_threshold": {"min": 0.55, "max": 0.80, "default": 0.70},
                    "surge_pct": {"min": 1.0, "max": 5.0, "default": 2.0},
                    "conf_ticks": {"min": 2, "max": 5, "default": 3},
                    "balance": {"min": 5, "max": 100, "default": 10},
                    "auto_stop": {"options": [1, 2, 4, 6], "default": 1},
                },
            },
        ],
    },
    "stairscreener": {
        "strategies": [
            {
                "id": "stair_climber",
                "engine": "trading",
                "label": "Лесенка",
                "description": "Для: крутой slope, трендовое движение, ступенчатый рост",
                "wizard_params": {
                    "timeframe": {"options": ["1m", "3m", "5m", "15m"], "default": "3m"},
                    "leverage": {"min": 1, "max": 5, "default": 3},
                    "stoploss": {"min": 1.0, "max": 5.0, "default": 2.0},
                    "takeprofit": {"min": 3.0, "max": 10.0, "default": 5.0},
                    "balance": {"min": 5, "max": 100, "default": 10},
                    "duration": {"options": [0.5, 1, 2, 4, 6], "default": 1},
                    "trend_filter": {"options": ["on", "off"], "default": "on"},
                    "min_confidence": {"min": 0.1, "max": 0.5, "default": 0.3},
                },
            },
            {
                "id": "ers_scalping",
                "engine": "ob",
                "label": "Ёршик",
                "description": "Для: консолидация, малый range, частые касания границ",
                "wizard_params": {
                    "stoploss": {"min": -3.0, "max": -0.5, "default": -1.5},
                    "trailing_stop": {"min": 0.1, "max": 1.0, "default": 0.3},
                    "conf_ticks": {"min": 1, "max": 5, "default": 1},
                    "max_spread": {"min": 0.05, "max": 0.5, "default": 0.1},
                    "max_hold": {"min": 30, "max": 300, "default": 120},
                    "cooldown": {"min": 30, "max": 300, "default": 30},
                },
            },
        ],
    },
}


def get_strategies_for_channel(channel: str) -> list[dict[str, Any]]:
    """Get the 2 strategy options for a given channel.

    Args:
        channel: 'brushscreener' or 'stairscreener'

    Returns:
        List of 2 strategy dicts, or empty list if channel unknown.
    """
    entry = CHANNEL_STRATEGIES.get(channel)
    if entry is None:
        return []
    return entry["strategies"]


def format_param_for_prompt(param_name: str, param_config: dict[str, Any]) -> str:
    """Format a single wizard param into a human-readable range string."""
    if "options" in param_config:
        opts = "/".join(str(o) for o in param_config["options"])
        return f"  {param_name}: {opts}"
    return f"  {param_name}: {param_config['min']}~{param_config['max']}"


def format_strategy_for_prompt(strategy: dict[str, Any]) -> str:
    """Format a strategy option for the LLM prompt."""
    lines = [f"{strategy['id']} ({strategy['engine']})"]
    lines.append(f"  {strategy['description']}")
    lines.append(f"  Параметры:")
    for param_name, param_config in strategy["wizard_params"].items():
        lines.append(format_param_for_prompt(param_name, param_config))
    return "\n".join(lines)


def build_llm_prompt(
    channel: str,
    pair: str,
    price_range: float | None,
    vol_60m: float | None,
    vol_10m: float | None,
    slope: float | None,
    top_ratio: float | None,
    bot_ratio: float | None,
) -> str | None:
    """Build the LLM classification prompt with exactly 2 strategy options.

    Returns:
        Prompt string, or None if channel has no configured strategies.
    """
    strategies = get_strategies_for_channel(channel)
    if len(strategies) < 2:
        return None

    # Format signal data
    def fmt(val, suffix="") -> str:
        if val is None:
            return "—"
        return f"{val}{suffix}"

    signal_lines = [
        f"Сигнал: {channel}, {pair}",
        f"range: {fmt(price_range, '%')}  vol60m: {fmt('$'+format(int(vol_60m), ',') if vol_60m and vol_60m >= 1000 else vol_60m)}  vol10m: {fmt('$'+format(int(vol_10m), ',') if vol_10m and vol_10m >= 1000 else vol_10m)}",
        f"slope: {fmt(slope)}  top_ratio: {fmt(top_ratio)}  bot_ratio: {fmt(bot_ratio)}",
    ]

    strategy_blocks = []
    labels = ["A", "B"]
    for label, strat in zip(labels, strategies):
        strategy_blocks.append(f"\n{label} — {format_strategy_for_prompt(strat)}")

    prompt = (
        "\n".join(signal_lines)
        + "\n"
        + "".join(strategy_blocks)
        + """

Ответь JSON:
{"variant":"A","strategy":"название","confidence":0.0-1.0,"params":{},"reasoning":"1 фраза почему такой выбор, на русском, с цифрами"}
"""
    )

    return prompt
