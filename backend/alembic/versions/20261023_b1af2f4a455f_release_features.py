"""Релизные функции: настройки магазина, баннеры, поддержка, рефералы

Revision ID: b1af2f4a455f
Revises: c41e9b0d7a12
Create Date: 2026-10-23 09:39:11.581048
"""
from collections.abc import Sequence

import sqlalchemy as sa

from alembic import op

revision: str = 'b1af2f4a455f'
down_revision: str | None = 'c41e9b0d7a12'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table('banners',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('title', sa.String(length=80), nullable=False),
    sa.Column('text', sa.String(length=200), nullable=False),
    sa.Column('image_url', sa.String(length=1024), nullable=True),
    sa.Column('button_label', sa.String(length=40), nullable=True),
    sa.Column('link_url', sa.String(length=300), nullable=True),
    sa.Column('theme', sa.String(length=10), nullable=False),
    sa.Column('position', sa.Integer(), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('starts_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('ends_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_banners'))
    )
    op.create_index(op.f('ix_banners_position'), 'banners', ['position'], unique=False)
    op.create_table('support_messages',
    sa.Column('id', sa.Integer(), nullable=False),
    sa.Column('user_id', sa.Integer(), nullable=False),
    sa.Column('staff_id', sa.Integer(), nullable=True),
    sa.Column('text', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('read_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['staff_id'], ['users.id'], name=op.f('fk_support_messages_staff_id_users'), ondelete='SET NULL'),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], name=op.f('fk_support_messages_user_id_users'), ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id', name=op.f('pk_support_messages'))
    )
    op.create_index(op.f('ix_support_messages_user_id'), 'support_messages', ['user_id'], unique=False)
    op.add_column('promo_codes', sa.Column('owner_user_id', sa.Integer(), nullable=True))
    op.add_column('promo_codes', sa.Column('source', sa.String(length=20), server_default='manual', nullable=False))
    op.add_column('promo_codes', sa.Column('first_order_only', sa.Boolean(), server_default='false', nullable=False))
    op.create_index(op.f('ix_promo_codes_owner_user_id'), 'promo_codes', ['owner_user_id'], unique=False)
    op.create_foreign_key(op.f('fk_promo_codes_owner_user_id_users'), 'promo_codes', 'users', ['owner_user_id'], ['id'], ondelete='CASCADE')
    op.add_column('shop_settings', sa.Column('contact_phone', sa.String(length=32), server_default='+7 (985) 394-72-62', nullable=False))
    op.add_column('shop_settings', sa.Column('contact_email', sa.String(length=120), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('delivery_min_order', sa.Numeric(precision=12, scale=2), server_default='2500', nullable=False))
    op.add_column('shop_settings', sa.Column('courier_fee', sa.Numeric(precision=12, scale=2), server_default='199', nullable=False))
    op.add_column('shop_settings', sa.Column('free_delivery_from', sa.Numeric(precision=12, scale=2), server_default='5000', nullable=True))
    op.add_column('shop_settings', sa.Column('express_enabled', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('shop_settings', sa.Column('express_fee', sa.Numeric(precision=12, scale=2), server_default='349', nullable=False))
    op.add_column('shop_settings', sa.Column('express_hours', sa.Integer(), server_default='2', nullable=False))
    op.add_column('shop_settings', sa.Column('pickup_enabled', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('shop_settings', sa.Column('referral_enabled', sa.Boolean(), server_default='true', nullable=False))
    op.add_column('shop_settings', sa.Column('referral_friend_amount', sa.Numeric(precision=12, scale=2), server_default='300', nullable=False))
    op.add_column('shop_settings', sa.Column('referral_inviter_amount', sa.Numeric(precision=12, scale=2), server_default='300', nullable=False))
    op.add_column('shop_settings', sa.Column('referral_min_order', sa.Numeric(precision=12, scale=2), server_default='2500', nullable=False))
    op.add_column('shop_settings', sa.Column('legal_name', sa.String(length=255), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('legal_inn', sa.String(length=12), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('legal_ogrn', sa.String(length=15), server_default='', nullable=False))
    op.add_column('shop_settings', sa.Column('legal_address', sa.String(length=300), server_default='', nullable=False))
    op.add_column('users', sa.Column('referral_code', sa.String(length=16), nullable=True))
    op.add_column('users', sa.Column('referred_by_id', sa.Integer(), nullable=True))
    op.add_column('users', sa.Column('referral_rewarded', sa.Boolean(), server_default='false', nullable=False))
    op.create_unique_constraint(op.f('uq_users_referral_code'), 'users', ['referral_code'])
    op.create_foreign_key(op.f('fk_users_referred_by_id_users'), 'users', 'users', ['referred_by_id'], ['id'], ondelete='SET NULL')


def downgrade() -> None:
    op.drop_constraint(op.f('fk_users_referred_by_id_users'), 'users', type_='foreignkey')
    op.drop_constraint(op.f('uq_users_referral_code'), 'users', type_='unique')
    op.drop_column('users', 'referral_rewarded')
    op.drop_column('users', 'referred_by_id')
    op.drop_column('users', 'referral_code')
    op.drop_column('shop_settings', 'legal_address')
    op.drop_column('shop_settings', 'legal_ogrn')
    op.drop_column('shop_settings', 'legal_inn')
    op.drop_column('shop_settings', 'legal_name')
    op.drop_column('shop_settings', 'referral_min_order')
    op.drop_column('shop_settings', 'referral_inviter_amount')
    op.drop_column('shop_settings', 'referral_friend_amount')
    op.drop_column('shop_settings', 'referral_enabled')
    op.drop_column('shop_settings', 'pickup_enabled')
    op.drop_column('shop_settings', 'express_hours')
    op.drop_column('shop_settings', 'express_fee')
    op.drop_column('shop_settings', 'express_enabled')
    op.drop_column('shop_settings', 'free_delivery_from')
    op.drop_column('shop_settings', 'courier_fee')
    op.drop_column('shop_settings', 'delivery_min_order')
    op.drop_column('shop_settings', 'contact_email')
    op.drop_column('shop_settings', 'contact_phone')
    op.drop_constraint(op.f('fk_promo_codes_owner_user_id_users'), 'promo_codes', type_='foreignkey')
    op.drop_index(op.f('ix_promo_codes_owner_user_id'), table_name='promo_codes')
    op.drop_column('promo_codes', 'first_order_only')
    op.drop_column('promo_codes', 'source')
    op.drop_column('promo_codes', 'owner_user_id')
    op.drop_index(op.f('ix_support_messages_user_id'), table_name='support_messages')
    op.drop_table('support_messages')
    op.drop_index(op.f('ix_banners_position'), table_name='banners')
    op.drop_table('banners')
