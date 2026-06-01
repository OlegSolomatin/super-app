"""add stop_loss_percent and take_profit_percent to trading_configs

Revision ID: 004_add_sl_tp
Revises: 003_create_telegram_bots
Create Date: 2026-06-02
"""
from alembic import op
import sqlalchemy as sa

revision = '004_add_sl_tp'
down_revision = '003_create_telegram_bots'
branch_labels = None
depends_on = None


def upgrade():
    op.add_column('trading_configs', sa.Column('stop_loss_percent', sa.Float(), nullable=True))
    op.add_column('trading_configs', sa.Column('take_profit_percent', sa.Float(), nullable=True))


def downgrade():
    op.drop_column('trading_configs', 'take_profit_percent')
    op.drop_column('trading_configs', 'stop_loss_percent')
