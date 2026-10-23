"""SEO: описание категории, регион доставки, коды подтверждения сайта

Revision ID: f2a7d4c9b351
Revises: e5b8c3d1a906
Create Date: 2026-10-24 14:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = 'f2a7d4c9b351'
down_revision: str | None = 'e5b8c3d1a906'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('categories', sa.Column('description', sa.Text(), server_default='', nullable=False))
    op.add_column(
        'shop_settings', sa.Column('delivery_area', sa.String(length=120), server_default='по Москве', nullable=False)
    )
    op.add_column('shop_settings', sa.Column('yandex_verification', sa.String(length=120), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('google_verification', sa.String(length=120), server_default='', nullable=False))


def downgrade() -> None:
    op.drop_column('shop_settings', 'google_verification')
    op.drop_column('shop_settings', 'yandex_verification')
    op.drop_column('shop_settings', 'delivery_area')
    op.drop_column('categories', 'description')
