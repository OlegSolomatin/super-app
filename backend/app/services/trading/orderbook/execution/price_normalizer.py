"""PriceNormalizer — коррекция цены при разных биржах данных и торговли.

Когда данные с Binance, а торгуем на Bybit:
  - Цена на Bybit может отличаться от Binance на 0.01-0.05%
  - При входе добавляем запас (slippage buffer)
  - При выходе корректируем по рынку исполнения

Когда данные и торговля на одной бирже:
  - Цена не корректируется (используем цену из снапшота)
"""
from __future__ import annotations

import logging
from typing import Optional

logger = logging.getLogger(__name__)

# Известные спреды между биржами (%)
# Если данные с X, а торгуем на Y — цена может отличаться
# Эти значения можно уточнять через REST API тикеров
CROSS_EXCHANGE_SPREADS: dict[tuple[str, str], float] = {
    ("binance", "bybit"): 0.03,   # Bybit обычно на 0.03% выше
    ("bybit", "binance"): -0.02,  # Binance может быть ниже на 0.02%
    ("binance", "binance"): 0.0,
    ("bybit", "bybit"): 0.0,
}

# Slippage буфер (% от цены) при входе/выходе
ENTRY_SLIPPAGE_BUFFER = 0.02   # +0.02% к цене для market buy
EXIT_SLIPPAGE_BUFFER = 0.02    # -0.02% от цены для market sell


class PriceNormalizer:
    """Корректирует цену при разных биржах данных и торговли.

    Использование:
        normalizer = PriceNormalizer(source_exchange="binance", trade_exchange="bybit")
        entry_price = normalizer.adjust_entry_price(signal_price, "BUY")
        exit_price = normalizer.adjust_exit_price(bid_price, "BUY")
    """

    def __init__(
        self,
        source_exchange: str,
        trade_exchange: str,
    ):
        self.source = source_exchange.lower().strip()
        self.target = trade_exchange.lower().strip()

        # Спред между биржами
        pair = (self.source, self.target)
        self._cross_spread = CROSS_EXCHANGE_SPREADS.get(pair, 0.05)
        if pair not in CROSS_EXCHANGE_SPREADS:
            logger.warning(
                f"[PriceNormalizer] Unknown spread for {self.source}→{self.target}, "
                f"using default 0.05%"
            )

        self._is_same = (self.source == self.target)

        logger.info(
            f"[PriceNormalizer] {self.source}→{self.target}: "
            f"cross_spread={self._cross_spread:+.3f}%"
        )

    @property
    def needs_correction(self) -> bool:
        """Нужна ли коррекция цены (разные биржи)."""
        return not self._is_same

    def adjust_entry_price(self, price: float, side: str) -> float:
        """Скорректировать цену входа.

        Если данные с Binance, а торгуем на Bybit:
          BUY:  price * (1 + cross_spread/100 + slippage/100)
          SELL: price * (1 + cross_spread/100 - slippage/100)

        Args:
            price: Цена из снапшота (source exchange).
            side: "BUY" или "SELL".

        Returns:
            Скорректированная цена для ордера.
        """
        if not self.needs_correction:
            return price

        if price <= 0:
            return price

        spread_factor = 1.0 + self._cross_spread / 100
        slip_factor = 1.0 + ENTRY_SLIPPAGE_BUFFER / 100
        slip_factor_sell = 1.0 - ENTRY_SLIPPAGE_BUFFER / 100

        if side == "BUY":
            return price * spread_factor * slip_factor
        else:
            return price * spread_factor * slip_factor_sell

    def adjust_exit_price(self, price: float, side: str) -> float:
        """Скорректировать цену выхода.

        Для sell: чуть ниже, чтобы гарантированно исполниться.
        Для buy: чуть выше.
        """
        if not self.needs_correction:
            return price

        if price <= 0:
            return price

        spread_factor = 1.0 + self._cross_spread / 100
        slip_factor = 1.0 - EXIT_SLIPPAGE_BUFFER / 100
        slip_factor_sell = 1.0 + EXIT_SLIPPAGE_BUFFER / 100

        if side == "BUY":
            return price * spread_factor * slip_factor
        else:
            return price * spread_factor * slip_factor_sell

    def __repr__(self) -> str:
        return (
            f"PriceNormalizer({self.source}→{self.target}, "
            f"spread={self._cross_spread:+.3f}%)"
        )
