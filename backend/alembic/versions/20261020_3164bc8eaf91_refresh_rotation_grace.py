"""Ротация refresh-токенов: refresh_tokens.rotated_at (повтор в первые 30 с — обрыв ответа, а не кража)

Revision ID: 3164bc8eaf91
Revises: 8db007efaeac
Create Date: 2026-10-20 07:50:43.702646
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = '3164bc8eaf91'
down_revision: str | None = '8db007efaeac'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column('refresh_tokens', sa.Column('rotated_at', sa.DateTime(timezone=True), nullable=True))


def downgrade() -> None:
    op.drop_column('refresh_tokens', 'rotated_at')
