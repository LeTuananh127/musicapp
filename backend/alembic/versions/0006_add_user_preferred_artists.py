"""add user_preferred_artists table

Revision ID: 0006_add_user_preferred_artists
Revises: 0005_merge_0004_heads
Create Date: 2025-10-21 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0006_add_user_preferred_artists'
down_revision = '0005_merge_0004_heads'
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        'user_preferred_artists',
        sa.Column('user_id', sa.Integer(), nullable=False),
        sa.Column('artist_id', sa.Integer(), nullable=False),
        sa.Column('created_at', sa.DateTime(), nullable=True),
        sa.PrimaryKeyConstraint('user_id', 'artist_id'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
        sa.ForeignKeyConstraint(['artist_id'], ['artists.id'], ),
    )


def downgrade():
    op.drop_table('user_preferred_artists')
