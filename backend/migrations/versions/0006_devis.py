"""devis

Revision ID: 0006
Revises: 0005
Create Date: 2026-11-01 13:52:55.543724
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0006'
down_revision = '0005'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('estimate_versions',
    sa.Column('estimate_id', sa.UUID(), nullable=False),
    sa.Column('project_id', sa.UUID(), nullable=False),
    sa.Column('version_no', sa.Integer(), nullable=False),
    sa.Column('status', sa.String(length=12), nullable=False),
    sa.Column('reference', sa.String(length=40), nullable=True),
    sa.Column('title', sa.String(length=200), nullable=False),
    sa.Column('issue_date', sa.Date(), nullable=False),
    sa.Column('validity_days', sa.Integer(), nullable=False),
    sa.Column('currency', sa.String(length=3), nullable=False),
    sa.Column('exchange_rate_e4', sa.BigInteger(), nullable=True),
    sa.Column('exchange_rate_date', sa.Date(), nullable=True),
    sa.Column('exchange_rate_source', sa.String(length=200), nullable=False),
    sa.Column('discount_bp', sa.Integer(), nullable=False),
    sa.Column('overhead_bp', sa.Integer(), nullable=False),
    sa.Column('margin_bp', sa.Integer(), nullable=False),
    sa.Column('deposit_bp', sa.Integer(), nullable=False),
    sa.Column('lines', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('totals', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('metre_fingerprint', sa.String(length=64), nullable=True),
    sa.Column('validated_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('validated_by', sa.UUID(), nullable=True),
    sa.Column('sent_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('decided_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('decision_note', sa.Text(), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("currency = 'MAD' OR exchange_rate_e4 > 0", name='ck_estimate_versions_rate'),
    sa.CheckConstraint("currency IN ('MAD', 'EUR')", name='ck_estimate_versions_currency'),
    sa.CheckConstraint("status = 'draft' OR reference IS NOT NULL", name='ck_estimate_versions_number'),
    sa.CheckConstraint("status IN ('draft', 'validated', 'sent', 'accepted', 'refused', 'superseded')", name='ck_estimate_versions_status'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['validated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('estimate_id', 'version_no', name='uq_estimate_versions_version'),
    sa.UniqueConstraint('organization_id', 'reference', name='uq_estimate_versions_reference')
    )
    op.create_index(op.f('ix_estimate_versions_estimate_id'), 'estimate_versions', ['estimate_id'], unique=False)
    op.create_index(op.f('ix_estimate_versions_organization_id'), 'estimate_versions', ['organization_id'], unique=False)
    op.create_index(op.f('ix_estimate_versions_project_id'), 'estimate_versions', ['project_id'], unique=False)
    op.create_index(op.f('ix_estimate_versions_sync_seq'), 'estimate_versions', ['sync_seq'], unique=False)

    op.execute(
        "CREATE TRIGGER estimate_versions_sync_seq BEFORE INSERT OR UPDATE ON estimate_versions "
        "FOR EACH ROW EXECUTE FUNCTION assign_sync_seq()"
    )
    op.execute("ALTER TABLE estimate_versions ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE estimate_versions FORCE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY estimate_versions_organization ON estimate_versions "
        "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
        "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
    )
    # Une version validée, envoyée ou décidée est figée (USER_FLOWS A6.2).
    op.execute(
        """
        CREATE FUNCTION estimate_versions_frozen() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            IF TG_OP = 'DELETE' THEN
                IF OLD.status <> 'draft' THEN
                    RAISE EXCEPTION 'devis figé : suppression interdite';
                END IF;
                RETURN OLD;
            END IF;
            IF OLD.status <> 'draft' AND (
                NEW.lines IS DISTINCT FROM OLD.lines OR NEW.totals IS DISTINCT FROM OLD.totals
                OR NEW.currency IS DISTINCT FROM OLD.currency OR NEW.exchange_rate_e4 IS DISTINCT FROM OLD.exchange_rate_e4
                OR NEW.discount_bp IS DISTINCT FROM OLD.discount_bp OR NEW.overhead_bp IS DISTINCT FROM OLD.overhead_bp
                OR NEW.margin_bp IS DISTINCT FROM OLD.margin_bp OR NEW.deposit_bp IS DISTINCT FROM OLD.deposit_bp
                OR NEW.issue_date IS DISTINCT FROM OLD.issue_date OR NEW.validity_days IS DISTINCT FROM OLD.validity_days
                OR NEW.reference IS DISTINCT FROM OLD.reference OR NEW.project_id IS DISTINCT FROM OLD.project_id
                OR NEW.estimate_id IS DISTINCT FROM OLD.estimate_id OR NEW.version_no IS DISTINCT FROM OLD.version_no
                OR NEW.metre_fingerprint IS DISTINCT FROM OLD.metre_fingerprint OR NEW.deleted_at IS NOT NULL
                OR NEW.status = 'draft'
            ) THEN
                RAISE EXCEPTION 'devis figé : créez une nouvelle version';
            END IF;
            RETURN NEW;
        END;
        $$;
        CREATE TRIGGER estimate_versions_frozen BEFORE UPDATE OR DELETE ON estimate_versions
            FOR EACH ROW EXECUTE FUNCTION estimate_versions_frozen();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS estimate_versions_frozen ON estimate_versions")
    op.execute("DROP FUNCTION IF EXISTS estimate_versions_frozen()")
    op.execute("DROP POLICY IF EXISTS estimate_versions_organization ON estimate_versions")
    op.execute("DROP TRIGGER IF EXISTS estimate_versions_sync_seq ON estimate_versions")
    op.drop_index(op.f('ix_estimate_versions_sync_seq'), table_name='estimate_versions')
    op.drop_index(op.f('ix_estimate_versions_project_id'), table_name='estimate_versions')
    op.drop_index(op.f('ix_estimate_versions_organization_id'), table_name='estimate_versions')
    op.drop_index(op.f('ix_estimate_versions_estimate_id'), table_name='estimate_versions')
    op.drop_table('estimate_versions')
