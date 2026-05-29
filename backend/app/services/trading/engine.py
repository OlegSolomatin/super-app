"""Trading engine — orchestrates the strategy execution loop.

Runs a strategy against historical or live data, manages positions,
and collects performance metrics.
"""

from __future__ import annotations

from app.services.trading.models import (
    Candle,
    Metrics,
    TradingConfig,
    TradingRun,
)


class TradingEngine:
    """Strategy execution engine.

    Responsibilities:
    - Fetch candles via data loader
    - Compute indicators
    - Feed candles into strategy
    - Execute signals (or log them)
    - Track trades and compute metrics
    """

    def __init__(self, config: TradingConfig) -> None:
        self.config = config
        self.run = TradingRun(config=config)

    async def run_history(self) -> Metrics:
        """Run strategy against historical data and return metrics."""
        # TODO: implement historical backtest loop
        return Metrics()

    async def run_virtual(self) -> Metrics:
        """Run strategy with live data on virtual balance."""
        # TODO: implement virtual trading loop
        return Metrics()

    async def run_real(self) -> Metrics:
        """Run strategy with live data on real balance via exchange."""
        # TODO: implement real trading loop
        return Metrics()

    async def stop(self) -> None:
        """Gracefully stop the running engine."""
        # TODO: implement graceful shutdown
        pass
