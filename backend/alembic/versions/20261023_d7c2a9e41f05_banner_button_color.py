"""Цвет кнопки баннера

Revision ID: d7c2a9e41f05
Revises: b1af2f4a455f
Create Date: 2026-10-23 18:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = 'd7c2a9e41f05'
down_revision: str | None = 'b1af2f4a455f'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('banners', sa.Column('button_color', sa.String(length=10), server_default='orange', nullable=False))


def downgrade() -> None:
    op.drop_column('banners', 'button_color')
