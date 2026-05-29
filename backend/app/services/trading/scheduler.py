"""Scheduler — manages up to 15 concurrent trading strategies.

Each scheduled run is tracked by run_id and can be started, stopped,
or queried for status.
"""

from __future__ import annotations

from typing import Dict, Optional

from app.services.trading.engine import TradingEngine
from app.services.trading.models import TradingConfig, TradingRunStatus


class TradingScheduler:
    """Manages concurrent trading strategy runs (max 15)."""

    MAX_RUNS = 15

    def __init__(self) -> None:
        self._runs: Dict[int, TradingEngine] = {}

    async def start(self, config: TradingConfig) -> int:
        """Create and start a new trading run.

        Returns the run_id. Raises RuntimeError if at capacity.
        """
        if len(self._runs) >= self.MAX_RUNS:
            raise RuntimeError("Maximum number of concurrent runs reached (15).")
        # TODO: implement run creation and start
        run_id = len(self._runs) + 1
        engine = TradingEngine(config)
        self._runs[run_id] = engine
        return run_id

    async def stop(self, run_id: int) -> None:
        """Stop a running strategy by run_id."""
        engine = self._runs.get(run_id)
        if engine:
            await engine.stop()
            del self._runs[run_id]

    async def get_status(self, run_id: int) -> Optional[TradingRunStatus]:
        """Return current status of a run, or None if not found."""
        engine = self._runs.get(run_id)
        if engine:
            return engine.run.status
        return None

    async def list_runs(self) -> Dict[int, TradingRunStatus]:
        """Return a mapping of run_id -> status for all active runs."""
        return {rid: eng.run.status for rid, eng in self._runs.items()}


# Singleton scheduler instance
scheduler = TradingScheduler()
