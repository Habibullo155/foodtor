"""Истории («кружочки» на главной): stories + story_slides

Revision ID: 46e90970bc1b
Revises: 3164bc8eaf91
Create Date: 2026-10-20 07:59:13.882328
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = '46e90970bc1b'
down_revision: str | None = '3164bc8eaf91'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('stories',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=40), nullable=False),
    sa.Column('cover_url', sa.String(length=1024), nullable=False),
    sa.Column('color_hex', sa.String(length=7), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('starts_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('ends_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.CheckConstraint("color_hex ~ '^#[0-9A-Fa-f]{6}$'", name=op.f('ck_stories_color_hex')),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_stories'))
    )
    op.create_index(op.f('ix_stories_position'), 'stories', ['position'], unique=False)
    op.create_table('story_slides',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('story_id', sa.Integer(), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('image_url', sa.String(length=1024), nullable=False),
    sa.Column('headline', sa.String(length=120), nullable=False),
    sa.Column('caption', sa.Text(), nullable=True),
    sa.Column('cta_label', sa.String(length=40), nullable=True),
    sa.Column('cta_url', sa.String(length=300), nullable=True),
    sa.ForeignKeyConstraint(['story_id'], ['stories.id'], name=op.f('fk_story_slides_story_id_stories'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_story_slides'))
    )
    op.create_index(op.f('ix_story_slides_story_id'), 'story_slides', ['story_id'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_story_slides_story_id'), table_name='story_slides')
    op.drop_table('story_slides')
    op.drop_index(op.f('ix_stories_position'), table_name='stories')
    op.drop_table('stories')
