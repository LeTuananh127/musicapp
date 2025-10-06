"""add cover_url to tracks

Revision ID: 0003_add_cover_url
Revises: 0002_add_milestone
Create Date: 2025-10-07
"""
from __future__ import annotations
from alembic import op
import sqlalchemy as sa

revision = '0003_add_cover_url'
down_revision = '0002_add_milestone'
branch_labels = None
depends_on = None

def upgrade():
    with op.batch_alter_table('tracks') as batch_op:
        batch_op.add_column(sa.Column('cover_url', sa.String(length=500), nullable=True))

def downgrade():
    with op.batch_alter_table('tracks') as batch_op:
        batch_op.drop_column('cover_url')
