"""
Initial seed data for the super-app database.

Run after migrations to populate default roles.
Usage:
    python -m app.seeds.initial_data
"""

from __future__ import annotations

import asyncio

from sqlalchemy import select

from app.core.database import async_session_factory
from app.models.user import Role


DEFAULT_ROLES = [
    {"name": "admin", "description": "Administrator with full system access"},
    {"name": "user", "description": "Standard registered user"},
]


async def seed_roles() -> None:
    """Create default roles if they don't exist."""
    async with async_session_factory() as session:
        for role_data in DEFAULT_ROLES:
            result = await session.execute(
                select(Role).where(Role.name == role_data["name"])
            )
            existing = result.scalar_one_or_none()
            if existing is None:
                role = Role(**role_data)
                session.add(role)
                print(f"  ✅ Created role: {role_data['name']}")
            else:
                print(f"  ⏭️  Role already exists: {role_data['name']}")

        await session.commit()

    print("✅ Seeding complete.")


async def main() -> None:
    """Entry point for seeding."""
    print("🌱 Seeding default data...")
    await seed_roles()


if __name__ == "__main__":
    asyncio.run(main())
