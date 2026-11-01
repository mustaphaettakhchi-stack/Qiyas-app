"""clients projets et synchronisation

Revision ID: 0003
Revises: 0002
Create Date: 2026-11-01 11:49:48.017578
"""

from alembic import op
import sqlalchemy as sa


revision = '0003'
down_revision = '0002'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('org_counters',
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('name', sa.String(length=30), nullable=False),
    sa.Column('year', sa.Integer(), nullable=False),
    sa.Column('value', sa.Integer(), nullable=False),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.PrimaryKeyConstraint('organization_id', 'name', 'year')
    )
    op.create_table('clients',
    sa.Column('type', sa.String(length=20), nullable=False),
    sa.Column('display_name', sa.String(length=200), nullable=False),
    sa.Column('phone', sa.String(length=30), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('address', sa.Text(), nullable=False),
    sa.Column('city', sa.String(length=100), nullable=False),
    sa.Column('ice', sa.String(length=15), nullable=False),
    sa.Column('notes', sa.Text(), nullable=False),
    sa.Column('consent_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('consent_text_version', sa.String(length=20), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("type IN ('individual', 'company')", name='ck_clients_type'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_clients_organization_id'), 'clients', ['organization_id'], unique=False)
    op.create_index(op.f('ix_clients_sync_seq'), 'clients', ['sync_seq'], unique=False)
    op.create_table('projects',
    sa.Column('reference', sa.String(length=30), nullable=False),
    sa.Column('client_id', sa.UUID(), nullable=True),
    sa.Column('name', sa.String(length=200), nullable=False),
    sa.Column('project_type', sa.String(length=20), nullable=False),
    sa.Column('property_kind', sa.String(length=20), nullable=True),
    sa.Column('status', sa.String(length=20), nullable=False),
    sa.Column('description', sa.Text(), nullable=False),
    sa.Column('budget_cents', sa.BigInteger(), nullable=True),
    sa.Column('currency', sa.String(length=3), nullable=False),
    sa.Column('visit_date', sa.Date(), nullable=True),
    sa.Column('manager_id', sa.UUID(), nullable=True),
    sa.Column('site_address', sa.Text(), nullable=False),
    sa.Column('site_city', sa.String(length=100), nullable=False),
    sa.Column('notes', sa.Text(), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("currency IN ('MAD', 'EUR')", name='ck_projects_currency'),
    sa.CheckConstraint("project_type IN ('renovation', 'new_build', 'extension', 'interior', 'exterior', 'commercial')", name='ck_projects_type'),
    sa.CheckConstraint("property_kind IS NULL OR property_kind IN ('apartment', 'house', 'villa', 'land', 'commercial', 'other')", name='ck_projects_kind'),
    sa.CheckConstraint("status IN ('prospect', 'visit_planned', 'estimating', 'estimate_sent', 'won', 'in_progress', 'delivered', 'lost', 'archived')", name='ck_projects_status'),
    sa.CheckConstraint('budget_cents IS NULL OR budget_cents >= 0', name='ck_projects_budget'),
    sa.ForeignKeyConstraint(['client_id'], ['clients.id'], ),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['manager_id'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('organization_id', 'reference', name='uq_projects_reference')
    )
    op.create_index(op.f('ix_projects_client_id'), 'projects', ['client_id'], unique=False)
    op.create_index(op.f('ix_projects_manager_id'), 'projects', ['manager_id'], unique=False)
    op.create_index(op.f('ix_projects_organization_id'), 'projects', ['organization_id'], unique=False)
    op.create_index(op.f('ix_projects_sync_seq'), 'projects', ['sync_seq'], unique=False)
    op.add_column('organizations', sa.Column('reference_prefix', sa.String(length=10), server_default='LMA', nullable=False))

    # Synchronisation : numéro d'ordre attribué à chaque écriture, sous verrou par organisation,
    # pour que l'ordre des numéros soit l'ordre de validation (aucune écriture manquée au tirage).
    op.execute("CREATE SEQUENCE sync_seq")
    op.execute(
        """
        CREATE FUNCTION assign_sync_seq() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            PERFORM pg_advisory_xact_lock(hashtextextended(NEW.organization_id::text, 0));
            NEW.sync_seq := nextval('sync_seq');
            RETURN NEW;
        END;
        $$;
        """
    )
    for table in ("clients", "projects"):
        op.execute(
            f"CREATE TRIGGER {table}_sync_seq BEFORE INSERT OR UPDATE ON {table} "
            "FOR EACH ROW EXECUTE FUNCTION assign_sync_seq()"
        )
        # Sécurité au niveau des lignes : défense en profondeur derrière les filtres de l'API.
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table}_organization ON {table} "
            "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
            "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
        )



def downgrade() -> None:
    for table in ("clients", "projects"):
        op.execute(f"DROP POLICY IF EXISTS {table}_organization ON {table}")
        op.execute(f"DROP TRIGGER IF EXISTS {table}_sync_seq ON {table}")
    op.execute("DROP FUNCTION IF EXISTS assign_sync_seq()")
    op.execute("DROP SEQUENCE IF EXISTS sync_seq")
    op.drop_column('organizations', 'reference_prefix')
    op.drop_index(op.f('ix_projects_sync_seq'), table_name='projects')
    op.drop_index(op.f('ix_projects_organization_id'), table_name='projects')
    op.drop_index(op.f('ix_projects_manager_id'), table_name='projects')
    op.drop_index(op.f('ix_projects_client_id'), table_name='projects')
    op.drop_table('projects')
    op.drop_index(op.f('ix_clients_sync_seq'), table_name='clients')
    op.drop_index(op.f('ix_clients_organization_id'), table_name='clients')
    op.drop_table('clients')
    op.drop_table('org_counters')
