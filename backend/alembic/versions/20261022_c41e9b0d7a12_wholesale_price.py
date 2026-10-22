"""Оптовая цена товара и минимальный заказ оптовика

Revision ID: c41e9b0d7a12
Revises: 8a3f6d1c2b77
Create Date: 2026-10-22 18:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = 'c41e9b0d7a12'
down_revision: str | None = '8a3f6d1c2b77'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('products', sa.Column('wholesale_price', sa.Numeric(precision=12, scale=2), nullable=True))
    op.create_check_constraint(op.f('ck_products_wholesale_non_negative'), 'products', 'wholesale_price IS NULL OR wholesale_price >= 0')
    op.add_column('shop_settings', sa.Column('wholesale_min_order', sa.Numeric(precision=12, scale=2), server_default='5000', nullable=False))


def downgrade() -> None:
    op.drop_column('shop_settings', 'wholesale_min_order')
    op.drop_constraint(op.f('ck_products_wholesale_non_negative'), 'products', type_='check')
    op.drop_column('products', 'wholesale_price')
