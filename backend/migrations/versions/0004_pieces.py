"""pieces

Revision ID: 0004
Revises: 0003
Create Date: 2026-11-01 12:17:09.702958
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0004'
down_revision = '0003'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('rooms',
    sa.Column('project_id', sa.UUID(), nullable=False),
    sa.Column('name', sa.String(length=100), nullable=False),
    sa.Column('level_name', sa.String(length=30), nullable=False),
    sa.Column('height_m', sa.Numeric(precision=6, scale=3), nullable=False),
    sa.Column('height_source', sa.String(length=10), nullable=False),
    sa.Column('walls', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('openings', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.Column('plan_x', sa.Numeric(precision=8, scale=2), nullable=True),
    sa.Column('plan_y', sa.Numeric(precision=8, scale=2), nullable=True),
    sa.Column('computed_floor_area_m2', sa.Numeric(precision=10, scale=3), nullable=False),
    sa.Column('computed_perimeter_m', sa.Numeric(precision=10, scale=3), nullable=False),
    sa.Column('closure_error_m', sa.Numeric(precision=8, scale=3), nullable=False),
    sa.Column('calc_version', sa.Integer(), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('created_by', sa.UUID(), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_by', sa.UUID(), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('sync_seq', sa.BigInteger(), server_default='0', nullable=False),
    sa.CheckConstraint("height_source IN ('manual', 'laser', 'default')", name='ck_rooms_height_source'),
    sa.CheckConstraint('height_m > 0 AND height_m <= 20', name='ck_rooms_height'),
    sa.ForeignKeyConstraint(['created_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['project_id'], ['projects.id'], ),
    sa.ForeignKeyConstraint(['updated_by'], ['users.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_rooms_organization_id'), 'rooms', ['organization_id'], unique=False)
    op.create_index(op.f('ix_rooms_project_id'), 'rooms', ['project_id'], unique=False)
    op.create_index(op.f('ix_rooms_sync_seq'), 'rooms', ['sync_seq'], unique=False)

    op.execute(
        "CREATE TRIGGER rooms_sync_seq BEFORE INSERT OR UPDATE ON rooms "
        "FOR EACH ROW EXECUTE FUNCTION assign_sync_seq()"
    )
    op.execute("ALTER TABLE rooms ENABLE ROW LEVEL SECURITY")
    op.execute("ALTER TABLE rooms FORCE ROW LEVEL SECURITY")
    op.execute(
        "CREATE POLICY rooms_organization ON rooms "
        "USING (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid) "
        "WITH CHECK (organization_id = NULLIF(current_setting('app.org_id', true), '')::uuid)"
    )


def downgrade() -> None:
    op.execute("DROP POLICY IF EXISTS rooms_organization ON rooms")
    op.execute("DROP TRIGGER IF EXISTS rooms_sync_seq ON rooms")
    op.drop_index(op.f('ix_rooms_sync_seq'), table_name='rooms')
    op.drop_index(op.f('ix_rooms_project_id'), table_name='rooms')
    op.drop_index(op.f('ix_rooms_organization_id'), table_name='rooms')
    op.drop_table('rooms')
