"""Курьеры: роль и право orders:deliver, назначение заказа, геопозиция, скрытый телефон, чат; города доставки

Revision ID: 767aa294084e
Revises: 3da7cd8f7cf0
Create Date: 2026-10-19 10:35:29.645006
"""
from collections.abc import Sequence

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision: str = '767aa294084e'
down_revision: str | None = '3da7cd8f7cf0'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Новое значение enum нельзя использовать в той же транзакции — добавляем отдельно (autocommit)
    with op.get_context().autocommit_block():
        op.execute("ALTER TYPE permission ADD VALUE IF NOT EXISTS 'orders:deliver'")
    op.add_column('order_comments', sa.Column('channel', sa.String(length=16), server_default='shop', nullable=False))
    op.create_index(op.f('ix_order_comments_channel'), 'order_comments', ['channel'], unique=False)
    op.add_column('orders', sa.Column('courier_id', sa.Integer(), nullable=True))
    op.add_column('orders', sa.Column('dest_lat', sa.Float(), nullable=True))
    op.add_column('orders', sa.Column('dest_lng', sa.Float(), nullable=True))
    op.add_column('orders', sa.Column('courier_lat', sa.Float(), nullable=True))
    op.add_column('orders', sa.Column('courier_lng', sa.Float(), nullable=True))
    op.add_column('orders', sa.Column('courier_seen_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('orders', sa.Column('phone_revealed_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('orders', sa.Column('phone_reveal_reason', sa.String(length=300), nullable=True))
    op.create_index(op.f('ix_orders_courier_id'), 'orders', ['courier_id'], unique=False)
    op.create_foreign_key(op.f('fk_orders_courier_id_users'), 'orders', 'users', ['courier_id'], ['id'], ondelete='SET NULL')
    op.add_column('shop_settings', sa.Column('delivery_cities', postgresql.JSONB(astext_type=sa.Text()), server_default='[]', nullable=False))


def downgrade() -> None:
    # Значение 'orders:deliver' в enum permission остаётся: PostgreSQL не умеет удалять значения enum
    op.execute("DELETE FROM role_permissions WHERE permission = 'orders:deliver'")
    op.drop_column('shop_settings', 'delivery_cities')
    op.drop_constraint(op.f('fk_orders_courier_id_users'), 'orders', type_='foreignkey')
    op.drop_index(op.f('ix_orders_courier_id'), table_name='orders')
    op.drop_column('orders', 'phone_reveal_reason')
    op.drop_column('orders', 'phone_revealed_at')
    op.drop_column('orders', 'courier_seen_at')
    op.drop_column('orders', 'courier_lng')
    op.drop_column('orders', 'courier_lat')
    op.drop_column('orders', 'dest_lng')
    op.drop_column('orders', 'dest_lat')
    op.drop_column('orders', 'courier_id')
    op.drop_index(op.f('ix_order_comments_channel'), table_name='order_comments')
    op.drop_column('order_comments', 'channel')
