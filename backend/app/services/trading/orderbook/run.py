"""Скрипт запуска Order Book Engine.

Usage:
    python3 -m app.services.trading.orderbook.run
    python3 -m app.services.trading.orderbook.run --pair ETHUSDT \\
        --strategy imbalance_scalping --balance 500
"""
from __future__ import annotations

import argparse
import asyncio
import logging
import signal

from app.services.trading.orderbook.engine import OrderBookEngine
from app.services.trading.orderbook.models import OrderBookConfig

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
)
logger = logging.getLogger("run")


def main():
    parser = argparse.ArgumentParser(description="Order Book Engine")
    parser.add_argument("--pair", default="BTCUSDT")
    parser.add_argument("--strategy", default="imbalance_scalping")
    parser.add_argument("--balance", type=float, default=1000.0)
    parser.add_argument("--max-trades", type=int, default=1)
    args = parser.parse_args()

    config = OrderBookConfig(
        pairs=[args.pair],
        initial_balance=args.balance,
        max_open_trades=args.max_trades,
    )
    config.strategy_name = args.strategy

    engine = OrderBookEngine(config)

    def shutdown():
        logger.info("Shutting down...")
        asyncio.create_task(engine.stop())

    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, shutdown)

    try:
        loop.run_until_complete(engine.start())
        loop.run_forever()
    except KeyboardInterrupt:
        pass
    finally:
        loop.run_until_complete(engine.stop())
        loop.close()


if __name__ == "__main__":
    main()
