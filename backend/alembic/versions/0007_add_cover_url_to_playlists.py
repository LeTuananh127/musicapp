"""add cover_url to playlists

Revision ID: 0007_add_cover_url_to_playlists
Revises: 0006_add_user_preferred_artists
Create Date: 2025-11-07
"""
from __future__ import annotations
from alembic import op
import sqlalchemy as sa

revision = '0007_add_cover_url_to_playlists'
down_revision = '0006_add_user_preferred_artists'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('playlists') as batch_op:
        batch_op.add_column(sa.Column('cover_url', sa.String(length=500), nullable=True))


def downgrade():
    with op.batch_alter_table('playlists') as batch_op:
        batch_op.drop_column('cover_url')
