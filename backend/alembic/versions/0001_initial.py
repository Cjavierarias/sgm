"""Initial migration: create core tables

Revision ID: 0001_initial
Revises: 
Create Date: 2026-05-30
"""
from alembic import op
import sqlalchemy as sa


# revision identifiers, used by Alembic.
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Create enum type for workorder status
    workorderstatus = sa.Enum('open', 'assigned', 'in_progress', 'closed', name='workorderstatus')
    workorderstatus.create(op.get_bind(), checkfirst=True)

    op.create_table(
        'companies',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('google_workspace_id', sa.String(length=255), nullable=True),
        sa.Column('status', sa.String(length=50), nullable=True, server_default='active'),
    )

    op.create_table(
        'users',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('company_id', sa.Integer(), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
        sa.Column('email', sa.String(length=255), nullable=False),
        sa.Column('hashed_password', sa.String(length=255), nullable=False),
        sa.Column('role', sa.String(length=50), nullable=True, server_default='technician'),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'equipments',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('company_id', sa.Integer(), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
        sa.Column('code', sa.String(length=100), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('location', sa.String(length=255), nullable=True),
        sa.Column('brand', sa.String(length=100), nullable=True),
        sa.Column('model', sa.String(length=100), nullable=True),
        sa.Column('manual_drive_url', sa.String(length=1000), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'work_orders',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('company_id', sa.Integer(), sa.ForeignKey('companies.id', ondelete='CASCADE'), nullable=False),
        sa.Column('equipment_id', sa.Integer(), sa.ForeignKey('equipments.id', ondelete='SET NULL'), nullable=True),
        sa.Column('assigned_to_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('status', workorderstatus, nullable=False, server_default='open'),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )

    op.create_table(
        'equipment_photos',
        sa.Column('id', sa.Integer(), primary_key=True),
        sa.Column('equipment_id', sa.Integer(), sa.ForeignKey('equipments.id', ondelete='CASCADE'), nullable=False),
        sa.Column('drive_url', sa.String(length=1000), nullable=False),
        sa.Column('uploaded_by_id', sa.Integer(), sa.ForeignKey('users.id', ondelete='SET NULL'), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('now()')),
    )

    # Indexes
    op.create_index(op.f('ix_users_email'), 'users', ['email'], unique=True)
    op.create_index(op.f('ix_equipments_code'), 'equipments', ['code'], unique=False)


def downgrade() -> None:
    op.drop_index(op.f('ix_equipments_code'), table_name='equipments')
    op.drop_index(op.f('ix_users_email'), table_name='users')

    op.drop_table('equipment_photos')
    op.drop_table('work_orders')
    op.drop_table('equipments')
    op.drop_table('users')
    op.drop_table('companies')

    # Drop enum type
    workorderstatus = sa.Enum('open', 'assigned', 'in_progress', 'closed', name='workorderstatus')
    workorderstatus.drop(op.get_bind(), checkfirst=True)
