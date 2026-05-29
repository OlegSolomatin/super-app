#!/usr/bin/env python3
"""Seed: create admin user and assign admin role."""
import asyncio
import sys
from pathlib import Path

# Add backend to path
sys.path.insert(0, str(Path(__file__).parent))

from app.core.database import async_session_factory, engine
from app.core.security import get_password_hash
from app.models.user import User, Role, UserRole
from sqlalchemy import select


async def seed():
    async with async_session_factory() as session:
        # Get admin role
        result = await session.execute(select(Role).where(Role.name == "admin"))
        admin_role = result.scalar_one_or_none()
        if not admin_role:
            print("❌ Admin role not found — run migration first")
            return

        # Get or create admin user
        result = await session.execute(select(User).where(User.email == "admin@super.app"))
        admin_user = result.scalar_one_or_none()

        if admin_user:
            print(f"✅ Admin user already exists: {admin_user.email}")
        else:
            admin_user = User(
                email="admin@super.app",
                username="admin",
                password_hash=get_password_hash("admin123"),
                bio="Super-App administrator",
            )
            session.add(admin_user)
            await session.flush()
            print(f"✅ Admin user created: admin@super.app / admin123")

        # Assign admin role
        result = await session.execute(
            select(UserRole).where(
                UserRole.user_id == admin_user.id,
                UserRole.role_id == admin_role.id,
            )
        )
        if result.scalar_one_or_none():
            print(f"✅ Admin role already assigned")
        else:
            session.add(UserRole(user_id=admin_user.id, role_id=admin_role.id))
            print(f"✅ Admin role assigned")

        await session.commit()
        print(f"\n🎉 Admin ready: admin@super.app / admin123")


asyncio.run(seed())
