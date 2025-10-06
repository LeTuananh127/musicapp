"""add milestone column to interactions

Revision ID: 0002_add_milestone
Revises: 0001_initial
Create Date: 2025-10-07
"""
from __future__ import annotations

from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '0002_add_milestone'
down_revision = '0001_initial'
branch_labels = None
depends_on = None


def upgrade():
    # Add nullable milestone column and index (matches ORM: Integer, nullable, index=True)
    with op.batch_alter_table('interactions') as batch_op:
        batch_op.add_column(sa.Column('milestone', sa.Integer(), nullable=True))
        batch_op.create_index('ix_interactions_milestone', ['milestone'])


def downgrade():
    with op.batch_alter_table('interactions') as batch_op:
        batch_op.drop_index('ix_interactions_milestone')
        batch_op.drop_column('milestone')
