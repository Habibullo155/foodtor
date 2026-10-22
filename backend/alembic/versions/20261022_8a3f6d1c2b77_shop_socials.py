"""Соцсети магазина: shop_settings.telegram_url/instagram_url

Revision ID: 8a3f6d1c2b77
Revises: 5c1e2b7a9d40
Create Date: 2026-10-22 14:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = '8a3f6d1c2b77'
down_revision: str | None = '5c1e2b7a9d40'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('shop_settings', sa.Column('telegram_url', sa.String(length=200), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('instagram_url', sa.String(length=200), server_default='', nullable=False))


def downgrade() -> None:
    op.drop_column('shop_settings', 'instagram_url')
    op.drop_column('shop_settings', 'telegram_url')
