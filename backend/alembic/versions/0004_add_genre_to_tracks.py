"""add genre_id and genre_name to tracks

Revision ID: 0004_add_genre_to_tracks
Revises: 0003_add_cover_url_to_tracks
Create Date: 2025-10-15 00:00:00.000000
"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0004_add_genre_to_tracks'
down_revision = '0003_add_cover_url'
branch_labels = None
depends_on = None


def upgrade():
    with op.batch_alter_table('tracks') as batch_op:
        batch_op.add_column(sa.Column('genre_id', sa.Integer(), nullable=True))
        batch_op.add_column(sa.Column('genre_name', sa.String(length=120), nullable=True))


def downgrade():
    with op.batch_alter_table('tracks') as batch_op:
        batch_op.drop_column('genre_name')
        batch_op.drop_column('genre_id')
