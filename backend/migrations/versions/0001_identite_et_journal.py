"""identite et journal

Revision ID: 0001
Revises: 
Create Date: 2026-11-01 09:12:43.109207
"""

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0001'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table('organizations',
    sa.Column('legal_name', sa.String(length=200), nullable=False),
    sa.Column('trade_name', sa.String(length=200), nullable=False),
    sa.Column('ice', sa.String(length=15), nullable=True),
    sa.Column('if_number', sa.String(length=30), nullable=True),
    sa.Column('rc', sa.String(length=30), nullable=True),
    sa.Column('patente', sa.String(length=30), nullable=True),
    sa.Column('cnss', sa.String(length=30), nullable=True),
    sa.Column('address', sa.Text(), nullable=False),
    sa.Column('city', sa.String(length=100), nullable=False),
    sa.Column('country', sa.String(length=2), nullable=False),
    sa.Column('phone', sa.String(length=30), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('default_currency', sa.String(length=3), nullable=False),
    sa.Column('estimate_validity_days', sa.Integer(), nullable=False),
    sa.Column('estimate_footer', sa.Text(), nullable=False),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.PrimaryKeyConstraint('id'),
    sa.CheckConstraint("default_currency IN ('MAD', 'EUR')", name='ck_organizations_currency'),
    sa.CheckConstraint("ice IS NULL OR ice ~ '^[0-9]{15}$'", name='ck_organizations_ice'),
    )
    op.create_table('audit_logs',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=True),
    sa.Column('occurred_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('actor_id', sa.UUID(), nullable=True),
    sa.Column('actor_role', sa.String(length=20), nullable=True),
    sa.Column('action', sa.String(length=60), nullable=False),
    sa.Column('entity_table', sa.String(length=60), nullable=True),
    sa.Column('entity_id', sa.UUID(), nullable=True),
    sa.Column('project_id', sa.UUID(), nullable=True),
    sa.Column('ip', sa.String(length=45), nullable=True),
    sa.Column('details', postgresql.JSONB(astext_type=sa.Text()), nullable=False),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_audit_logs_action'), 'audit_logs', ['action'], unique=False)
    op.create_index(op.f('ix_audit_logs_occurred_at'), 'audit_logs', ['occurred_at'], unique=False)
    op.create_index(op.f('ix_audit_logs_organization_id'), 'audit_logs', ['organization_id'], unique=False)
    op.create_table('users',
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('password_hash', sa.String(length=255), nullable=False),
    sa.Column('password_changed_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('totp_secret_enc', sa.Text(), nullable=True),
    sa.Column('totp_enabled', sa.Boolean(), nullable=False),
    sa.Column('totp_last_step', sa.BigInteger(), nullable=True),
    sa.Column('full_name', sa.String(length=200), nullable=False),
    sa.Column('phone', sa.String(length=30), nullable=False),
    sa.Column('locale', sa.String(length=5), nullable=False),
    sa.Column('status', sa.Enum('active', 'suspended', name='user_status'), nullable=False),
    sa.Column('last_login_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('failed_login_count', sa.Integer(), nullable=False),
    sa.Column('locked_until', sa.DateTime(timezone=True), nullable=True),
    sa.Column('client_id', sa.UUID(), nullable=True),
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('version', sa.Integer(), server_default='1', nullable=False),
    sa.Column('deleted_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('email')
    )
    op.create_index(op.f('ix_users_organization_id'), 'users', ['organization_id'], unique=False)
    op.create_table('auth_sessions',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('refresh_token_hash', sa.String(length=64), nullable=False),
    sa.Column('previous_token_hash', sa.String(length=64), nullable=True),
    sa.Column('device_label', sa.String(length=100), nullable=False),
    sa.Column('ip', sa.String(length=45), nullable=True),
    sa.Column('user_agent', sa.String(length=300), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('last_used_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('revoke_reason', sa.String(length=50), nullable=True),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('refresh_token_hash')
    )
    op.create_index(op.f('ix_auth_sessions_organization_id'), 'auth_sessions', ['organization_id'], unique=False)
    op.create_index(op.f('ix_auth_sessions_previous_token_hash'), 'auth_sessions', ['previous_token_hash'], unique=False)
    op.create_index(op.f('ix_auth_sessions_user_id'), 'auth_sessions', ['user_id'], unique=False)
    op.create_table('invitations',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('email', sa.String(length=254), nullable=False),
    sa.Column('full_name', sa.String(length=200), nullable=False),
    sa.Column('role', sa.Enum('admin', 'collaborator', 'client', name='user_role'), nullable=False),
    sa.Column('client_id', sa.UUID(), nullable=True),
    sa.Column('token_hash', sa.String(length=64), nullable=False),
    sa.Column('invited_by', sa.UUID(), nullable=False),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.Column('expires_at', sa.DateTime(timezone=True), nullable=False),
    sa.Column('accepted_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
    sa.ForeignKeyConstraint(['invited_by'], ['users.id'], ),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('token_hash')
    )
    op.create_index(op.f('ix_invitations_organization_id'), 'invitations', ['organization_id'], unique=False)
    op.create_table('mfa_backup_codes',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('code_hash', sa.String(length=64), nullable=False),
    sa.Column('used_at', sa.DateTime(timezone=True), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id')
    )
    op.create_index(op.f('ix_mfa_backup_codes_user_id'), 'mfa_backup_codes', ['user_id'], unique=False)
    op.create_table('user_roles',
    sa.Column('id', sa.UUID(), nullable=False),
    sa.Column('organization_id', sa.UUID(), nullable=False),
    sa.Column('user_id', sa.UUID(), nullable=False),
    sa.Column('role', postgresql.ENUM('admin', 'collaborator', 'client', name='user_role', create_type=False), nullable=False),
    sa.Column('scope_project_id', sa.UUID(), nullable=True),
    sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()'), nullable=False),
    sa.ForeignKeyConstraint(['organization_id'], ['organizations.id'], ),
    sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
    sa.PrimaryKeyConstraint('id'),
    sa.UniqueConstraint('user_id', 'role', 'scope_project_id', postgresql_nulls_not_distinct=True)
    )
    op.create_index(op.f('ix_user_roles_organization_id'), 'user_roles', ['organization_id'], unique=False)
    op.create_index(op.f('ix_user_roles_user_id'), 'user_roles', ['user_id'], unique=False)

    # Journal d'audit en insertion seule (SECURITY.md §9).
    op.execute(
        """
        CREATE FUNCTION audit_logs_immutable() RETURNS trigger LANGUAGE plpgsql AS $$
        BEGIN
            RAISE EXCEPTION 'audit_logs est en insertion seule';
        END;
        $$;
        CREATE TRIGGER audit_logs_no_update_delete
            BEFORE UPDATE OR DELETE ON audit_logs
            FOR EACH ROW EXECUTE FUNCTION audit_logs_immutable();
        CREATE TRIGGER audit_logs_no_truncate
            BEFORE TRUNCATE ON audit_logs
            FOR EACH STATEMENT EXECUTE FUNCTION audit_logs_immutable();
        """
    )


def downgrade() -> None:
    op.execute("DROP TRIGGER IF EXISTS audit_logs_no_truncate ON audit_logs")
    op.execute("DROP TRIGGER IF EXISTS audit_logs_no_update_delete ON audit_logs")
    op.execute("DROP FUNCTION IF EXISTS audit_logs_immutable()")
    op.drop_index(op.f('ix_user_roles_user_id'), table_name='user_roles')
    op.drop_index(op.f('ix_user_roles_organization_id'), table_name='user_roles')
    op.drop_table('user_roles')
    op.drop_index(op.f('ix_mfa_backup_codes_user_id'), table_name='mfa_backup_codes')
    op.drop_table('mfa_backup_codes')
    op.drop_index(op.f('ix_invitations_organization_id'), table_name='invitations')
    op.drop_table('invitations')
    op.drop_index(op.f('ix_auth_sessions_user_id'), table_name='auth_sessions')
    op.drop_index(op.f('ix_auth_sessions_previous_token_hash'), table_name='auth_sessions')
    op.drop_index(op.f('ix_auth_sessions_organization_id'), table_name='auth_sessions')
    op.drop_table('auth_sessions')
    op.drop_index(op.f('ix_users_organization_id'), table_name='users')
    op.drop_table('users')
    op.drop_index(op.f('ix_audit_logs_organization_id'), table_name='audit_logs')
    op.drop_index(op.f('ix_audit_logs_occurred_at'), table_name='audit_logs')
    op.drop_index(op.f('ix_audit_logs_action'), table_name='audit_logs')
    op.drop_table('audit_logs')
    op.drop_table('organizations')
    op.execute("DROP TYPE IF EXISTS user_role")
    op.execute("DROP TYPE IF EXISTS user_status")
