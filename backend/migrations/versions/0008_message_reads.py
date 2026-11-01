"""messages non lus

Revision ID: 0008
Revises: 0007
Create Date: 2026-11-01 18:30:00
"""
from alembic import op
import sqlalchemy as sa

revision = '0008'
down_revision = '0007'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('message_reads',
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('project_id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('read_at', sa.DateTime(timezone=True), nullable=False),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ),
    sa.PrimaryKeyConstraint('user_id', 'project_id')
    )
    op.create_index(op.f('ix_message_reads_organization_id'), 'message_reads', ['organization_id'], unique=False)
    op.execute("ALTER TABLE message_reads ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE message_reads FORCE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY message_reads_organization ON message_reads "
        "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
        "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS message_reads_organization ON message_reads")
    op.drop_index(op.f('ix_message_reads_organization_id'), table_name='message_reads')
    op.drop_table('message_reads')
