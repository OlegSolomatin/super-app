"""add trend filter columns to trading configs

Revision ID: dccc74600b45
Revises: 004_add_sl_tp
Create Date: 2026-06-02 08:20:47.096613
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = 'dccc74600b45'
down_revision: Union[str, None] = '004_add_sl_tp'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column('trading_configs', sa.Column('trend_filter_enabled', sa.Boolean(), server_default=sa.text('true'), nullable=False))
    op.add_column('trading_configs', sa.Column('trend_filter_period', sa.Integer(), server_default=sa.text('200'), nullable=False))


def downgrade() -> None:
    op.drop_column('trading_configs', 'trend_filter_period')
    op.drop_column('trading_configs', 'trend_filter_enabled')
