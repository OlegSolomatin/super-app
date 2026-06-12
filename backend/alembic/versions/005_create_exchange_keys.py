"""create exchange_keys table for storing encrypted API keys

Revision ID: 005_create_exchange_keys
Revises: 004_add_sl_tp
Create Date: 2026-06-12 02:40:00.000000
"""

from __future__ import annotations

from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "005_create_exchange_keys"
down_revision: Union[str, None] = "c249fa55656c"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "exchange_keys",
        sa.Column("id", sa.UUID(), nullable=False),
        sa.Column(
            "user_id",
            sa.UUID(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
            index=True,
        ),
        sa.Column("exchange", sa.String(20), nullable=False),
        sa.Column("label", sa.String(100), server_default="", nullable=True),
        sa.Column("api_key_encrypted", sa.Text(), nullable=False),
        sa.Column("api_secret_encrypted", sa.Text(), nullable=False),
        sa.Column("passphrase", sa.Text(), nullable=True),
        sa.Column("is_active", sa.Boolean(), server_default="true", nullable=False),
        sa.Column(
            "status",
            sa.String(20),
            server_default="untested",
            nullable=False,
        ),
        sa.Column("balance", sa.Float(), nullable=True),
        sa.Column("balance_updated_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
        sa.Column("last_checked_at", sa.DateTime(timezone=True), nullable=True),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_exchange_keys_user_exchange",
        "exchange_keys",
        ["user_id", "exchange"],
        unique=True,
        postgresql_where=sa.text("is_active = true"),
    )


def downgrade() -> None:
    op.drop_index("ix_exchange_keys_user_exchange")
    op.drop_table("exchange_keys")
