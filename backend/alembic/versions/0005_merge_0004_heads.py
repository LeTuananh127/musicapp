"""merge 0004 heads

Revision ID: 0005_merge_0004_heads
Revises: 0004_add_genre_to_tracks, 0004_add_spotify_track_id
Create Date: 2025-10-15
"""
from __future__ import annotations
from alembic import op
import sqlalchemy as sa

revision = '0005_merge_0004_heads'
down_revision = ('0004_add_genre_to_tracks', '0004_add_spotify_track_id')
branch_labels = None
depends_on = None


def upgrade():
    # merge revision - no DB changes
    pass


def downgrade():
    pass
