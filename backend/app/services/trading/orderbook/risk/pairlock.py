"""Блокировка пар после сделки.

freqtrade: PairLock model
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Optional


class PairLockManager:
    """In-memory блокировка пар."""

    def __init__(self):
        self._locks: dict[str, tuple[datetime, str]] = {}

    def lock(self, pair: str, until: datetime, reason: str = ""):
        self._locks[pair] = (until, reason)

    def is_locked(self, pair: str) -> bool:
        now = datetime.now(timezone.utc)
        if pair not in self._locks:
            return False
        until, _ = self._locks[pair]
        if now >= until:
            del self._locks[pair]
            return False
        return True

    def unlock(self, pair: str):
        self._locks.pop(pair, None)

    @property
    def active_locks(self) -> list[tuple[str, datetime, str]]:
        now = datetime.now(timezone.utc)
        return [(p, u, r) for p, (u, r) in self._locks.items() if u > now]
