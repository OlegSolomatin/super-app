"""add trading tables

Revision ID: 3836debca730
Revises: 002
Create Date: 2026-05-29 23:09:30.088328
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

# revision identifiers, used by Alembic.
revision: str = '3836debca730'
down_revision: Union[str, None] = '002'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    # --- trading_runs ---
    op.create_table('trading_runs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('user_id', sa.UUID(), nullable=False),
        sa.Column('status', sa.String(length=20), nullable=False),
        sa.Column('mode', sa.String(length=20), nullable=False),
        sa.Column('started_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.Column('finished_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('error', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_trading_runs_started_at', 'trading_runs', ['started_at'], unique=False)
    op.create_index(op.f('ix_trading_runs_status'), 'trading_runs', ['status'], unique=False)
    op.create_index(op.f('ix_trading_runs_user_id'), 'trading_runs', ['user_id'], unique=False)
    op.create_index('ix_trading_runs_user_status', 'trading_runs', ['user_id', 'status'], unique=False)

    # --- trading_configs ---
    op.create_table('trading_configs',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('run_id', sa.Integer(), nullable=False),
        sa.Column('pair', sa.String(length=20), nullable=False),
        sa.Column('strategy', sa.String(length=50), nullable=False),
        sa.Column('leverage', sa.Integer(), nullable=False),
        sa.Column('virtual_balance', sa.Float(), nullable=False),
        sa.Column('max_trade_amount', sa.Float(), nullable=False),
        sa.Column('timeframe', sa.String(length=10), nullable=False),
        sa.Column('period_start', sa.DateTime(timezone=True), nullable=True),
        sa.Column('period_end', sa.DateTime(timezone=True), nullable=True),
        sa.Column('duration_days', sa.Integer(), nullable=True),
        sa.Column('exchange', sa.String(length=50), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['run_id'], ['trading_runs.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('run_id'),
    )

    # --- trading_results ---
    op.create_table('trading_results',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('run_id', sa.Integer(), nullable=False),
        sa.Column('total_trades', sa.Integer(), nullable=False),
        sa.Column('win_trades', sa.Integer(), nullable=False),
        sa.Column('loss_trades', sa.Integer(), nullable=False),
        sa.Column('win_rate', sa.Float(), nullable=False),
        sa.Column('profit_loss', sa.Float(), nullable=False),
        sa.Column('final_balance', sa.Float(), nullable=False),
        sa.Column('max_drawdown', sa.Float(), nullable=False),
        sa.Column('metrics', postgresql.JSONB(astext_type=sa.Text()), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
        sa.ForeignKeyConstraint(['run_id'], ['trading_runs.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('run_id'),
    )

    # --- trading_trades ---
    op.create_table('trading_trades',
        sa.Column('id', sa.Integer(), autoincrement=True, nullable=False),
        sa.Column('run_id', sa.Integer(), nullable=False),
        sa.Column('side', sa.String(length=10), nullable=False),
        sa.Column('entry_price', sa.Float(), nullable=False),
        sa.Column('exit_price', sa.Float(), nullable=True),
        sa.Column('entry_time', sa.DateTime(timezone=True), nullable=False),
        sa.Column('exit_time', sa.DateTime(timezone=True), nullable=True),
        sa.Column('quantity', sa.Float(), nullable=False),
        sa.Column('pnl', sa.Float(), nullable=False),
        sa.Column('pnl_percent', sa.Float(), nullable=False),
        sa.Column('status', sa.String(length=10), nullable=False),
        sa.ForeignKeyConstraint(['run_id'], ['trading_runs.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_trading_trades_entry_time', 'trading_trades', ['entry_time'], unique=False)
    op.create_index(op.f('ix_trading_trades_run_id'), 'trading_trades', ['run_id'], unique=False)
    op.create_index('ix_trading_trades_run_status', 'trading_trades', ['run_id', 'status'], unique=False)
    op.create_index(op.f('ix_trading_trades_status'), 'trading_trades', ['status'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_trading_trades_status'), table_name='trading_trades')
    op.drop_index('ix_trading_trades_run_status', table_name='trading_trades')
    op.drop_index(op.f('ix_trading_trades_run_id'), table_name='trading_trades')
    op.drop_index('ix_trading_trades_entry_time', table_name='trading_trades')
    op.drop_table('trading_trades')
    op.drop_table('trading_results')
    op.drop_table('trading_configs')
    op.drop_index('ix_trading_runs_user_status', table_name='trading_runs')
    op.drop_index(op.f('ix_trading_runs_user_id'), table_name='trading_runs')
    op.drop_index(op.f('ix_trading_runs_status'), table_name='trading_runs')
    op.drop_index('ix_trading_runs_started_at', table_name='trading_runs')
    op.drop_table('trading_runs')
