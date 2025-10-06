"""initial schema

Revision ID: 0001_initial
Revises: 
Create Date: 2025-10-06
"""
from __future__ import annotations
from alembic import op
import sqlalchemy as sa

# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None

def upgrade():
    # NOTE: For brevity we only create a subset of tables explicitly. In practice, prefer autogenerate.
    op.create_table(
        'artists',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(length=255), nullable=False, unique=True),
        sa.Column('created_at', sa.DateTime(), server_default=sa.func.now(), nullable=False),
    )
    # Other tables will be produced via autogenerate in subsequent revisions.


def downgrade():
    op.drop_table('artists')
