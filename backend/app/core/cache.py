"""
Redis cache client for super-app.

Provides async caching utilities using redis-py.
Usage:
    from app.core.cache import get_cache, set_cache, delete_cache, clear_cache

    await set_cache("key", {"data": "value"}, ttl=300)
    data = await get_cache("key")
"""

from __future__ import annotations

import json
from typing import Any, Optional

from redis.asyncio import Redis

from app.core.config import settings

_redis: Optional[Redis] = None


def _get_client() -> Redis:
    """Get or create the Redis client singleton."""
    global _redis
    if _redis is None:
        _redis = Redis.from_url(
            settings.REDIS_URL,
            encoding="utf-8",
            decode_responses=True,
        )
    return _redis


async def get_cache(key: str) -> Optional[Any]:
    """Get a value from cache by key.

    Args:
        key: Cache key string.

    Returns:
        Deserialized value or None if key not found.
    """
    client = _get_client()
    value = await client.get(key)
    if value is None:
        return None
    try:
        return json.loads(value)
    except (json.JSONDecodeError, TypeError):
        return value


async def set_cache(key: str, value: Any, ttl: int = 300) -> None:
    """Set a value in cache with optional TTL.

    Args:
        key: Cache key string.
        value: Serializable value to cache.
        ttl: Time-to-live in seconds (default 5 minutes).
    """
    client = _get_client()
    serialized = json.dumps(value, default=str)
    await client.setex(key, ttl, serialized)


async def delete_cache(key: str) -> None:
    """Delete a specific key from cache.

    Args:
        key: Cache key string to delete.
    """
    client = _get_client()
    await client.delete(key)


async def clear_cache() -> None:
    """Flush the entire Redis cache."""
    client = _get_client()
    await client.flushdb()


async def close_redis() -> None:
    """Close the Redis connection pool (call on shutdown)."""
    global _redis
    if _redis is not None:
        await _redis.aclose()
        _redis = None
