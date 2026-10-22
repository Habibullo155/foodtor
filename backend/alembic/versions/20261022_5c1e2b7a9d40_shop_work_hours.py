"""Часы работы магазина: shop_settings.work_days/work_from/work_to

Revision ID: 5c1e2b7a9d40
Revises: 46e90970bc1b
Create Date: 2026-10-22 10:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = '5c1e2b7a9d40'
down_revision: str | None = '46e90970bc1b'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('shop_settings', sa.Column('work_days', postgresql.JSONB(astext_type=sa.Text()), server_default='[0,1,2,3,4,5]', nullable=False))
    op.add_column('shop_settings', sa.Column('work_from', sa.String(length=5), server_default='10:00', nullable=False))
    op.add_column('shop_settings', sa.Column('work_to', sa.String(length=5), server_default='22:00', nullable=False))


def downgrade() -> None:
    op.drop_column('shop_settings', 'work_to')
    op.drop_column('shop_settings', 'work_from')
    op.drop_column('shop_settings', 'work_days')
