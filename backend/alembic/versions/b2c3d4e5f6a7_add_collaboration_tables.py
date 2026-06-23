"""add collaboration tables (invitations, calendar_events, export_logs)

Revision ID: b2c3d4e5f6a7
Revises: a1b2c3d4e5f6
Create Date: 2026-06-23

Tablas nuevas:
  - invitations
  - calendar_events
  - export_logs
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "b2c3d4e5f6a7"
down_revision = "a1b2c3d4e5f6"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── invitations ────────────────────────────────────────────────────────────
    op.create_table(
        "invitations",
        sa.Column("id",               sa.Integer(),    primary_key=True),
        sa.Column("company_id",       sa.Integer(),    sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_by_id",    sa.Integer(),    sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("email",            sa.String(255),  nullable=False),
        sa.Column("token",            sa.String(64),   nullable=False, unique=True),
        sa.Column("roles_csv",        sa.String(255),  nullable=True),
        sa.Column("full_name",        sa.String(255),  nullable=True),
        sa.Column("status",           sa.String(20),   nullable=False, server_default="pending"),
        sa.Column("expires_at",       sa.DateTime(timezone=True), nullable=False),
        sa.Column("accepted_at",      sa.DateTime(timezone=True), nullable=True),
        sa.Column("accepted_user_id", sa.Integer(),    sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("created_at",       sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_invitations_company_id", "invitations", ["company_id"])
    op.create_index("ix_invitations_email",      "invitations", ["email"])
    op.create_index("ix_invitations_token",      "invitations", ["token"])
    op.create_index("ix_invitations_status",     "invitations", ["status"])

    # ── calendar_events ────────────────────────────────────────────────────────
    op.create_table(
        "calendar_events",
        sa.Column("id",                  sa.Integer(),    primary_key=True),
        sa.Column("company_id",          sa.Integer(),    sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("maintenance_plan_id", sa.Integer(),    sa.ForeignKey("maintenance_plans.id", ondelete="CASCADE"), nullable=True),
        sa.Column("work_order_id",       sa.Integer(),    sa.ForeignKey("work_orders.id", ondelete="CASCADE"), nullable=True),
        sa.Column("title",               sa.String(255),  nullable=False),
        sa.Column("description",         sa.Text(),       nullable=True),
        sa.Column("start_at",            sa.DateTime(timezone=True), nullable=False),
        sa.Column("end_at",              sa.DateTime(timezone=True), nullable=True),
        sa.Column("color",               sa.String(20),   nullable=True, server_default="#0077B6"),
        sa.Column("location",            sa.String(255),  nullable=True),
        sa.Column("google_event_id",     sa.String(255),  nullable=True),
        sa.Column("google_calendar_id",  sa.String(255),  nullable=True),
        sa.Column("synced_at",           sa.DateTime(timezone=True), nullable=True),
        sa.Column("created_at",          sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at",          sa.DateTime(timezone=True), nullable=True, onupdate=sa.func.now()),
    )
    op.create_index("ix_calendar_events_company_id",      "calendar_events", ["company_id"])
    op.create_index("ix_calendar_events_google_event_id", "calendar_events", ["google_event_id"])

    # ── export_logs ────────────────────────────────────────────────────────────
    op.create_table(
        "export_logs",
        sa.Column("id",            sa.Integer(),    primary_key=True),
        sa.Column("company_id",    sa.Integer(),    sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id",       sa.Integer(),    sa.ForeignKey("users.id", ondelete="SET NULL"), nullable=True),
        sa.Column("module",        sa.String(50),   nullable=False),
        sa.Column("sheet_id",      sa.String(255),  nullable=True),
        sa.Column("sheet_url",     sa.String(1000), nullable=True),
        sa.Column("rows_exported", sa.Integer(),    nullable=True),
        sa.Column("created_at",    sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_export_logs_company_id", "export_logs", ["company_id"])


def downgrade() -> None:
    op.drop_table("export_logs")
    op.drop_table("calendar_events")
    op.drop_table("invitations")
