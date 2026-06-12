"""CLI для backtesting OB-стратегий на записанных снапшотах.

Запускает OrderBookEngine с ReplayDataProvider вместо live WS.

Использование:
    python3 -m app.services.trading.orderbook.backtest.cli \\
        --snapshots data/ob_snapshots/BTCUSDT_imbalance_20260606.jsonl \\
        --strategy iceberg_detection \\
        --balance 1000 \\
        --speed 50.0

    Без --snapshots: записывает live-снапшоты в файл (режим записи)

Вариант B (из PLAN): симулятор стакана из свечей.
  Не реализован — используем только записанные live-снапшоты.
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import os
import signal
import sys
from datetime import datetime, timezone

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("backtest")


def main():
    parser = argparse.ArgumentParser(
        description="Backtest OB strategies on recorded snapshots"
    )
    parser.add_argument(
        "--snapshots", "-s",
        default="",
        help="Path to JSONL snapshot file. If empty, runs live mode with recording.",
    )
    parser.add_argument(
        "--pair", default="BTCUSDT",
        help="Trading pair (default: BTCUSDT)",
    )
    parser.add_argument(
        "--strategy", default="imbalance_scalping",
        choices=[
            "imbalance_scalping", "spread_capture",
            "order_flow_momentum", "ers_scalping",
            "iceberg_detection",
        ],
        help="Strategy to test",
    )
    parser.add_argument(
        "--balance", type=float, default=1000.0,
        help="Initial virtual balance",
    )
    parser.add_argument(
        "--speed", type=float, default=50.0,
        help="Replay speed multiplier (0 = max speed, default: 50x)",
    )
    parser.add_argument(
        "--record",
        action="store_true",
        help="Record snapshots to file during live run (use with --snapshots)",
    )
    args = parser.parse_args()

    if args.snapshots:
        # Режим backtest: воспроизводим записанные снапшоты
        asyncio.run(_run_backtest(args))
    else:
        # Режим live с записью
        logger.warning(
            "No --snapshots provided. Use --snapshots to replay recorded data.\n"
            "Starting live mode with recording... Use --record to save snapshots."
        )
        asyncio.run(_run_live(args))


async def _run_backtest(args):
    """Запустить backtest на записанных снапшотах."""
    from app.services.trading.orderbook.backtest.replay_provider import (
        ReplayDataProvider,
    )
    from app.services.trading.orderbook.engine import OrderBookEngine
    from app.services.trading.orderbook.models import OrderBookConfig

    if not os.path.exists(args.snapshots):
        logger.error(f"Snapshot file not found: {args.snapshots}")
        sys.exit(1)

    config = OrderBookConfig(
        pairs=[args.pair],
        strategy_name=args.strategy,
        initial_balance=args.balance,
        max_open_trades=1,
    )

    provider = ReplayDataProvider(
        filepath=args.snapshots,
        speed=args.speed,
    )

    engine = OrderBookEngine(config, fetcher=provider)

    start_balance = config.initial_balance
    start_time = datetime.now(timezone.utc)

    try:
        await engine.start()
    except KeyboardInterrupt:
        pass
    finally:
        await engine.stop()

    elapsed = (datetime.now(timezone.utc) - start_time).total_seconds()
    end_balance = engine.wallets.total_balance
    pnl = end_balance - start_balance
    pnl_pct = (pnl / start_balance * 100) if start_balance > 0 else 0.0
    trades = len(engine._trade_history)
    wins = engine.metrics["win_count"]
    losses = engine.metrics["loss_count"]
    win_rate = (wins / trades * 100) if trades > 0 else 0.0

    # Вывод результатов
    print("\n" + "=" * 50)
    print(f"📊 Backtest Results: {args.strategy} on {args.pair}")
    print("=" * 50)
    print(f"  Snapshots:     {os.path.basename(args.snapshots)}")
    print(f"  Replay speed:  {args.speed:.0f}x")
    print(f"  Duration:      {elapsed:.1f}s")
    print(f"  Trades:        {trades}")
    print(f"  Win/Loss:      {wins}/{losses}")
    print(f"  Win Rate:      {win_rate:.1f}%")
    print(f"  PnL:           ${pnl:.2f} ({pnl_pct:+.2f}%)")
    print(f"  Balance:       ${start_balance:.2f} → ${end_balance:.2f}")
    print(f"  Max Drawdown:  {engine.metrics['max_drawdown']:.2f}%")
    print(f"  Signals:       {engine.metrics['signals_generated']}")
    print("=" * 50 + "\n")


async def _run_live(args):
    """Запустить live режим с опциональной записью снапшотов."""
    from app.services.trading.orderbook.engine import OrderBookEngine
    from app.services.trading.orderbook.models import OrderBookConfig

    config = OrderBookConfig(
        pairs=[args.pair],
        strategy_name=args.strategy,
        initial_balance=args.balance,
        max_open_trades=1,
    )

    engine = OrderBookEngine(config)

    if args.record:
        from app.services.trading.orderbook.backtest.recorder import DataRecorder
        recorder = DataRecorder(
            pair=args.pair,
            strategy=args.strategy,
        )

        # Patch engine._on_snapshot to also record
        original_on_snapshot = engine._on_snapshot

        async def recording_on_snapshot(snap):
            recorder.record(snap)
            await original_on_snapshot(snap)

        engine._on_snapshot = recording_on_snapshot
        logger.info(f"Recording snapshots to {recorder.filepath}")

    def shutdown():
        logger.info("Shutting down...")
        asyncio.create_task(engine.stop())

    loop = asyncio.get_event_loop()
    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown)

    try:
        await engine.start()
    except KeyboardInterrupt:
        pass
    finally:
        await engine.stop()
        if args.record:
            recorder.close()


if __name__ == "__main__":
    main()
