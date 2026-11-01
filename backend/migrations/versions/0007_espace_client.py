"""espace client

Revision ID: 0007
Revises: 0006
Create Date: 2026-11-01 14:21:59.290563
"""

from alembic import op
import sqlalchemy as sa


revision = '0007'
down_revision = '0006'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('messages',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('project_id', sa.UUID(), nullable=False),
    sa.Column('author_id', sa.UUID(), nullable=False),
    sa.Column('from_client', sa.Boolean(), nullable=False),
    sa.Column('body', sa.Text(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['author_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_messages_created_at'), 'messages', ['created_at'], unique=False)
    op.create_index(op.f('ix_messages_organization_id'), 'messages', ['organization_id'], unique=False)
    op.create_index(op.f('ix_messages_project_id'), 'messages', ['project_id'], unique=False)
    op.create_table('files',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('project_id', sa.UUID(), nullable=False),
    sa.Column('quote_version_id', sa.UUID(), nullable=True),
    sa.Column('kind', sa.String(length=20), nullable=False),
    sa.Column('storage_key', sa.String(length=200), nullable=False),
    sa.Column('client_storage_key', sa.String(length=200), nullable=True),
    sa.Column('mime_type', sa.String(length=50), nullable=False),
    sa.Column('size_bytes', sa.BigInteger(), nullable=False),
    sa.Column('sha256', sa.String(length=64), nullable=False),
    sa.Column('caption', sa.String(length=300), nullable=False),
    sa.Column('visible_to_client', sa.Boolean(), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.CheckConstraint("kind IN ('photo', 'quote_pdf')", name='ck_files_kind'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ),
    sa.ForeignKeyConstraint(['quote_version_id'], ['estimate_versions.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('quote_version_id', name='uq_files_quote_pdf')
    )
    op.create_index(op.f('ix_files_organization_id'), 'files', ['organization_id'], unique=False)
    op.create_index(op.f('ix_files_project_id'), 'files', ['project_id'], unique=False)
    op.create_foreign_key('fk_invitations_client_id', 'invitations', 'clients', ['client_id'], ['id'])
    op.create_foreign_key('fk_users_client_id', 'users', 'clients', ['client_id'], ['id'])

    for table in ("files", "messages"):
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table}_organization ON {table} "
            "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
            "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
        )


def downgrade() -> None:
    for table in ("files", "messages"):
        op.execute(f"DROP POLICY IF EXISTS {table}_organization ON {table}")
    # WARNING: constraint name is None; this directive will fail as
    # rendered.  Add a name, or use a naming convention; see
    # https://alembic.sqlalchemy.org/en/latest/naming.html
    op.drop_constraint('fk_users_client_id', 'users', type_='foreignkey')
    # WARNING: constraint name is None; this directive will fail as
    # rendered.  Add a name, or use a naming convention; see
    # https://alembic.sqlalchemy.org/en/latest/naming.html
    op.drop_constraint('fk_invitations_client_id', 'invitations', type_='foreignkey')
    op.drop_index(op.f('ix_files_project_id'), table_name='files')
    op.drop_index(op.f('ix_files_organization_id'), table_name='files')
    op.drop_table('files')
    op.drop_index(op.f('ix_messages_project_id'), table_name='messages')
    op.drop_index(op.f('ix_messages_organization_id'), table_name='messages')
    op.drop_index(op.f('ix_messages_created_at'), table_name='messages')
    op.drop_table('messages')
