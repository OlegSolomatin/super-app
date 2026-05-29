"""create notifications table

Revision ID: 002
Revises: 001
Create Date: 2026-05-29
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = "002"
down_revision: Union[str, None] = "001"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    """Create notifications table and seed default roles."""
    # --- notifications table ---
    op.create_table(
        "notifications",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            primary_key=True,
            server_default=sa.text("gen_random_uuid()"),
        ),
        sa.Column(
            "user_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("type", sa.String(20), nullable=False),
        sa.Column("title", sa.String(255), nullable=False),
        sa.Column("body", sa.Text(), nullable=True),
        sa.Column(
            "is_read",
            sa.Boolean(),
            nullable=False,
            server_default=sa.text("false"),
        ),
        sa.Column(
            "related_id",
            postgresql.UUID(as_uuid=True),
            nullable=True,
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.func.now(),
            nullable=False,
        ),
    )
    op.create_index(
        "ix_notifications_user_read",
        "notifications",
        ["user_id", "is_read"],
    )
    op.create_index(
        "ix_notifications_created_at",
        "notifications",
        ["created_at"],
    )

    # --- seed default roles ---
    op.execute(
        sa.text(
            "INSERT INTO roles (name, description) "
            "VALUES ('admin', 'Administrator with full system access') "
            "ON CONFLICT (name) DO NOTHING;"
        )
    )
    op.execute(
        sa.text(
            "INSERT INTO roles (name, description) "
            "VALUES ('user', 'Standard registered user') "
            "ON CONFLICT (name) DO NOTHING;"
        )
    )


def downgrade() -> None:
    """Drop notifications table."""
    op.drop_index("ix_notifications_created_at", table_name="notifications")
    op.drop_index("ix_notifications_user_read", table_name="notifications")
    op.drop_table("notifications")
    # Note: default roles are NOT removed on downgrade to avoid data loss
