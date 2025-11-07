"""add created_by to artists

Revision ID: 0008_add_created_by_to_artists
Revises: 0007_add_cover_url_to_playlists
Create Date: 2025-11-07 00:00:00.000000

"""
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0008_add_created_by_to_artists'
down_revision = '0007_add_cover_url_to_playlists'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('artists', sa.Column('created_by', sa.Integer(), nullable=True))
    op.create_foreign_key('fk_artists_created_by_users', 'artists', 'users', ['created_by'], ['id'])


def downgrade() -> None:
    op.drop_constraint('fk_artists_created_by_users', 'artists', type_='foreignkey')
    op.drop_column('artists', 'created_by')
