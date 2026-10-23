"""Скрытые категории и справочник фирм

Revision ID: e5b8c3d1a906
Revises: d7c2a9e41f05
Create Date: 2026-10-24 10:00:00
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = 'e5b8c3d1a906'
down_revision: str | None = 'd7c2a9e41f05'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('categories', sa.Column('is_visible', sa.Boolean(), server_default='true', nullable=False))
    op.create_table(
        'brands',
        sa.Column('id', sa.Integer(), nullable=False),
        sa.Column('name', sa.String(length=120), nullable=False),
        sa.Column('logo_url', sa.String(length=1024), nullable=True),
        sa.PrimaryKeyConstraint('id', name=op.f('pk_brands')),
        sa.UniqueConstraint('name', name=op.f('uq_brands_name')),
    )


def downgrade() -> None:
    op.drop_table('brands')
    op.drop_column('categories', 'is_visible')
