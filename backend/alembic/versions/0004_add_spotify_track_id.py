"""add spotify_track_id (no-op placeholder)

This migration is a placeholder to match an existing revision id present in the database
so the alembic revision graph can be resolved. It intentionally performs no schema changes.

Revision ID: 0004_add_spotify_track_id
Revises: 0003_add_cover_url
Create Date: 2025-10-15
"""
from __future__ import annotations
from alembic import op
import sqlalchemy as sa

revision = '0004_add_spotify_track_id'
down_revision = '0003_add_cover_url'
branch_labels = None
depends_on = None


def upgrade():
    # no-op placeholder
    pass


def downgrade():
    # no-op placeholder
    pass
