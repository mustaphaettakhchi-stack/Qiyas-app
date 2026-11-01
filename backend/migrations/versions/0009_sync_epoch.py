"""époque de synchronisation (restauration de sauvegarde)

Revision ID: 0009
Revises: 0008
Create Date: 2026-11-01 19:40:00
"""
from alembic import op
import sqlalchemy as sa

revision = '0009'
down_revision = '0008'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column('organizations', sa.Column('sync_epoch', sa.UUID(), nullable=True))


def downgrade() -> None:
    op.drop_column('organizations', 'sync_epoch')
