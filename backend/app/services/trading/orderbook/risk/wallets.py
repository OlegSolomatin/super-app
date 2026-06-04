"""Управление балансом и расчёт размера ставки.

freqtrade: wallets.py
"""


class Wallets:
    """Виртуальный баланс.

    Формула ставки: free_balance / max_open_trades
    """

    def __init__(self, initial_balance: float = 1000.0,
                 max_open_trades: int = 1):
        self.initial_balance = initial_balance
        self.max_open_trades = max(max_open_trades, 1)
        self._free = initial_balance
        self._locked: dict[str, float] = {}

    def get_trade_stake_amount(self, pair: str) -> float:
        amount = self._free / self.max_open_trades
        if amount < 10.0:
            return 0.0
        return amount

    def lock_stake(self, pair: str, amount: float) -> None:
        self._free -= amount
        self._locked[pair] = amount

    def unlock_stake(self, pair: str, pnl: float) -> None:
        locked = self._locked.pop(pair, 0.0)
        self._free += locked + pnl

    @property
    def free_balance(self) -> float:
        return self._free

    @property
    def total_balance(self) -> float:
        return self._free + sum(self._locked.values())

    @property
    def locked_in_trades(self) -> dict[str, float]:
        return dict(self._locked)
