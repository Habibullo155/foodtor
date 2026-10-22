"""Вход по коду (SMS/email): users.phone_e164, email необязателен, email_verified_at, таблица кодов

Revision ID: 8db007efaeac
Revises: 767aa294084e
Create Date: 2026-10-20 03:16:06.153318
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = '8db007efaeac'
down_revision: str | None = '767aa294084e'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('login_codes',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('channel', sa.String(length=8), nullable=False),
    sa.Column('target', sa.String(length=255), nullable=False),
    sa.Column('code_hash', sa.String(length=64), nullable=False),
    sa.Column('ip', sa.String(length=64), nullable=True),
    sa.Column('attempts', sa.Integer(), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_login_codes'))
    )
    op.create_index(op.f('ix_login_codes_created_at'), 'login_codes', ['created_at'], unique=False)
    op.create_index(op.f('ix_login_codes_target'), 'login_codes', ['target'], unique=False)
    op.add_column('users', sa.Column('phone_e164', sa.String(length=16), nullable=True))
    op.add_column('users', sa.Column('phone_verified_at', sa.DateTime(timezone=True), nullable=True))
    op.add_column('users', sa.Column('email_verified_at', sa.DateTime(timezone=True), nullable=True))
    op.alter_column('users', 'email',
               existing_type=sa.VARCHAR(length=255),
               nullable=True)
    op.create_unique_constraint(op.f('uq_users_phone_e164'), 'users', ['phone_e164'])


def downgrade() -> None:
    op.drop_constraint(op.f('uq_users_phone_e164'), 'users', type_='unique')
    # у покупателей, вошедших по SMS, email нет — подставляем заглушку, иначе NOT NULL не вернуть
    op.execute("UPDATE users SET email = 'phone' || id || '@phone.invalid' WHERE email IS NULL")
    op.alter_column('users', 'email',
               existing_type=sa.VARCHAR(length=255),
               nullable=False)
    op.drop_column('users', 'email_verified_at')
    op.drop_column('users', 'phone_verified_at')
    op.drop_column('users', 'phone_e164')
    op.drop_index(op.f('ix_login_codes_target'), table_name='login_codes')
    op.drop_index(op.f('ix_login_codes_created_at'), table_name='login_codes')
    op.drop_table('login_codes')
