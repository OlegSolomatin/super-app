"""add_closed_trades_json_to_orderbook_runs

Revision ID: 344f3bf7b637
Revises: 6540cfcbd5e0
Create Date: 2026-06-08 12:28:34.415729
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision: str = '344f3bf7b637'
down_revision: Union[str, None] = '6540cfcbd5e0'
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        'orderbook_runs',
        sa.Column('closed_trades_json', sa.Text(), nullable=True)
    )


def downgrade() -> None:
    op.drop_column('orderbook_runs', 'closed_trades_json')
