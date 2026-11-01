"""bibliotheque et metre

Revision ID: 0005
Revises: 0004
Create Date: 2026-11-01 12:40:44.255620
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0005'
down_revision = '0004'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('suppliers',
    sa.Column('name', sa.String(length=200), nullable=False),
    sa.Column('contact_name', sa.String(length=200), nullable=False),
    sa.Column('phone', sa.String(length=30), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('address', sa.Text(), nullable=False),
    sa.Column('city', sa.String(length=100), nullable=False),
    sa.Column('ice', sa.String(length=15), nullable=False),
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
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_suppliers_organization_id'), 'suppliers', ['organization_id'], unique=False)
    op.create_index(op.f('ix_suppliers_sync_seq'), 'suppliers', ['sync_seq'], unique=False)
    op.create_table('work_items',
    sa.Column('code', sa.String(length=30), nullable=False),
    sa.Column('category', sa.String(length=20), nullable=False),
    sa.Column('name', sa.String(length=200), nullable=False),
    sa.Column('description', sa.Text(), nullable=False),
    sa.Column('unit', sa.String(length=10), nullable=False),
    sa.Column('quantity_basis', sa.String(length=20), nullable=False),
    sa.Column('count_key', sa.String(length=30), nullable=True),
    sa.Column('waste_rate_bp', sa.Integer(), nullable=False),
    sa.Column('labour_cost_cents', sa.BigInteger(), nullable=True),
    sa.Column('sale_price_cents', sa.BigInteger(), nullable=True),
    sa.Column('currency', sa.String(length=3), nullable=False),
    sa.Column('components', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('is_active', sa.Boolean(), nullable=False),
    sa.Column('price_note', sa.String(length=300), nullable=False),
    sa.Column('price_updated_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("(quantity_basis = 'count') = (count_key IS NOT NULL)", name='ck_work_items_count_basis'),
    sa.CheckConstraint("category IN ('floor', 'wall', 'ceiling', 'joinery', 'electricity', 'plumbing', 'masonry', 'other')", name='ck_work_items_category'),
    sa.CheckConstraint("count_key IS NULL OR count_key IN ('prises', 'interrupteurs', 'points_lumineux', 'points_eau', 'evacuations', 'sanitaires', 'placards', 'cloisons_m2', 'demolition_m2', 'reprises_m2', 'ouvertures_a_creer')", name='ck_work_items_count_key'),
    sa.CheckConstraint("currency IN ('MAD', 'EUR')", name='ck_work_items_currency'),
    sa.CheckConstraint("quantity_basis IN ('floor', 'ceiling', 'walls_net', 'walls_gross', 'skirting', 'perimeter', 'volume', 'doors', 'windows', 'count', 'manual')", name='ck_work_items_basis'),
    sa.CheckConstraint("unit IN ('m', 'm2', 'm3', 'kg', 'l', 'u', 'forfait')", name='ck_work_items_unit'),
    sa.CheckConstraint('labour_cost_cents IS NULL OR labour_cost_cents >= 0', name='ck_work_items_labour'),
    sa.CheckConstraint('sale_price_cents IS NULL OR sale_price_cents >= 0', name='ck_work_items_sale'),
    sa.CheckConstraint('waste_rate_bp BETWEEN 0 AND 10000', name='ck_work_items_waste'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_work_items_organization_id'), 'work_items', ['organization_id'], unique=False)
    op.create_index(op.f('ix_work_items_sync_seq'), 'work_items', ['sync_seq'], unique=False)
    op.create_table('materials',
    sa.Column('supplier_id', sa.UUID(), nullable=True),
    sa.Column('category', sa.String(length=20), nullable=False),
    sa.Column('name', sa.String(length=200), nullable=False),
    sa.Column('brand', sa.String(length=100), nullable=False),
    sa.Column('reference', sa.String(length=100), nullable=False),
    sa.Column('unit', sa.String(length=10), nullable=False),
    sa.Column('pack_size', sa.Numeric(precision=12, scale=3), nullable=True),
    sa.Column('waste_rate_bp', sa.Integer(), nullable=False),
    sa.Column('purchase_price_cents', sa.BigInteger(), nullable=True),
    sa.Column('sale_price_cents', sa.BigInteger(), nullable=True),
    sa.Column('currency', sa.String(length=3), nullable=False),
    sa.Column('city', sa.String(length=100), nullable=False),
    sa.Column('price_note', sa.String(length=300), nullable=False),
    sa.Column('price_updated_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("category IN ('floor', 'wall', 'ceiling', 'joinery', 'electricity', 'plumbing', 'masonry', 'other')", name='ck_materials_category'),
    sa.CheckConstraint("currency IN ('MAD', 'EUR')", name='ck_materials_currency'),
    sa.CheckConstraint("unit IN ('m', 'm2', 'm3', 'kg', 'l', 'u', 'forfait')", name='ck_materials_unit'),
    sa.CheckConstraint('purchase_price_cents IS NULL OR purchase_price_cents >= 0', name='ck_materials_purchase'),
    sa.CheckConstraint('sale_price_cents IS NULL OR sale_price_cents >= 0', name='ck_materials_sale'),
    sa.CheckConstraint('waste_rate_bp BETWEEN 0 AND 10000', name='ck_materials_waste'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['supplier_id'], ['suppliers.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_materials_organization_id'), 'materials', ['organization_id'], unique=False)
    op.create_index(op.f('ix_materials_supplier_id'), 'materials', ['supplier_id'], unique=False)
    op.create_index(op.f('ix_materials_sync_seq'), 'materials', ['sync_seq'], unique=False)
    op.create_table('price_history',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('material_id', sa.UUID(), nullable=True),
    sa.Column('work_item_id', sa.UUID(), nullable=True),
    sa.Column('purchase_price_cents', sa.BigInteger(), nullable=True),
    sa.Column('sale_price_cents', sa.BigInteger(), nullable=True),
    sa.Column('labour_cost_cents', sa.BigInteger(), nullable=True),
    sa.Column('currency', sa.String(length=3), nullable=False),
    sa.Column('supplier_id', sa.UUID(), nullable=True),
    sa.Column('city', sa.String(length=100), nullable=False),
    sa.Column('source_note', sa.String(length=300), nullable=False),
    sa.Column('recorded_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('recorded_by', sa.UUID(), nullable=False),
    sa.ForeignKeyConstraint(['material_id'], ['materials.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['recorded_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['supplier_id'], ['suppliers.id'], ),
    sa.ForeignKeyConstraint(['work_item_id'], ['work_items.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_price_history_material_id'), 'price_history', ['material_id'], unique=False)
    op.create_index(op.f('ix_price_history_organization_id'), 'price_history', ['organization_id'], unique=False)
    op.create_index(op.f('ix_price_history_work_item_id'), 'price_history', ['work_item_id'], unique=False)
    op.add_column('projects', sa.Column('metre_validation', postgresql.JSONB(astext_type=sa.Text()), nullable=True))
    op.add_column('rooms', sa.Column('counts', postgresql.JSONB(astext_type=sa.Text()), nullable=False, server_default=sa.text("'{}'::jsonb")))

    for table in ("suppliers", "materials", "work_items"):
        op.execute(
            f"CREATE TRIGGER {table}_sync_seq BEFORE INSERT OR UPDATE ON {table} "
            "FOR EACH ROW EXECUTE FUNCTION assign_sync_seq()"
        )
    for table in ("suppliers", "materials", "work_items", "price_history"):
        op.execute(f"ALTER TABLE {table} ENABLE ROW LEVEL SECURITY")
        op.execute(f"ALTER TABLE {table} FORCE ROW LEVEL SECURITY")
        op.execute(
            f"CREATE POLICY {table}_organization ON {table} "
            "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
            "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
        )
    # Historique des prix en insertion seule (même principe que le journal d'audit).
    op.execute(
        """
        CREATE FUNCTION price_history_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'price_history est en insertion seule';
        END;
        $$;
        CREATE TRIGGER price_history_no_update_delete BEFORE UPDATE OR DELETE ON price_history
            FOR EACH ROW EXECUTE FUNCTION price_history_immutable();
        CREATE TRIGGER price_history_no_truncate BEFORE TRUNCATE ON price_history
            FOR EACH STATEMENT EXECUTE FUNCTION price_history_immutable();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS price_history_no_truncate ON price_history")
    op.execute("DROP TRIGGER IF EXISTS price_history_no_update_delete ON price_history")
    op.execute("DROP FUNCTION IF EXISTS price_history_immutable()")
    for table in ("suppliers", "materials", "work_items", "price_history"):
        op.execute(f"DROP POLICY IF EXISTS {table}_organization ON {table}")
    for table in ("suppliers", "materials", "work_items"):
        op.execute(f"DROP TRIGGER IF EXISTS {table}_sync_seq ON {table}")
    op.drop_column('rooms', 'counts')
    op.drop_column('projects', 'metre_validation')
    op.drop_index(op.f('ix_price_history_work_item_id'), table_name='price_history')
    op.drop_index(op.f('ix_price_history_organization_id'), table_name='price_history')
    op.drop_index(op.f('ix_price_history_material_id'), table_name='price_history')
    op.drop_table('price_history')
    op.drop_index(op.f('ix_materials_sync_seq'), table_name='materials')
    op.drop_index(op.f('ix_materials_supplier_id'), table_name='materials')
    op.drop_index(op.f('ix_materials_organization_id'), table_name='materials')
    op.drop_table('materials')
    op.drop_index(op.f('ix_work_items_sync_seq'), table_name='work_items')
    op.drop_index(op.f('ix_work_items_organization_id'), table_name='work_items')
    op.drop_table('work_items')
    op.drop_index(op.f('ix_suppliers_sync_seq'), table_name='suppliers')
    op.drop_index(op.f('ix_suppliers_organization_id'), table_name='suppliers')
    op.drop_table('suppliers')
