"""add billing tables

Revision ID: a1b2c3d4e5f6
Revises: 9962ca20e2fb
Create Date: 2026-06-22

Tablas nuevas:
  - subscriptions
  - billing_events
  - blocked_admin_emails
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "a1b2c3d4e5f6"
down_revision = "9962ca20e2fb"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # ── subscriptions ──────────────────────────────────────────────────────────
    op.create_table(
        "subscriptions",
        sa.Column("id",                   sa.Integer(),     primary_key=True),
        sa.Column("company_id",           sa.Integer(),     sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=False, unique=True),
        sa.Column("admin_email",          sa.String(255),   nullable=False),
        sa.Column("plan",                 sa.String(50),    nullable=True,  server_default="monthly"),
        sa.Column("status",               sa.String(50),    nullable=False, server_default="trial"),
        sa.Column("trial_start",          sa.DateTime(timezone=True), nullable=False),
        sa.Column("trial_end",            sa.DateTime(timezone=True), nullable=False),
        sa.Column("current_period_start", sa.DateTime(timezone=True), nullable=True),
        sa.Column("current_period_end",   sa.DateTime(timezone=True), nullable=True),
        sa.Column("grace_start",          sa.DateTime(timezone=True), nullable=True),
        sa.Column("grace_end",            sa.DateTime(timezone=True), nullable=True),
        sa.Column("mp_subscription_id",   sa.String(255),   nullable=True),
        sa.Column("mp_preapproval_id",    sa.String(255),   nullable=True),
        sa.Column("mp_payer_email",       sa.String(255),   nullable=True),
        sa.Column("created_at",           sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("updated_at",           sa.DateTime(timezone=True), nullable=True,  onupdate=sa.func.now()),
    )
    op.create_index("ix_subscriptions_company_id",    "subscriptions", ["company_id"])
    op.create_index("ix_subscriptions_admin_email",   "subscriptions", ["admin_email"])
    op.create_index("ix_subscriptions_status",        "subscriptions", ["status"])
    op.create_index("ix_subscriptions_mp_sub_id",     "subscriptions", ["mp_subscription_id"])

    # ── billing_events ─────────────────────────────────────────────────────────
    op.create_table(
        "billing_events",
        sa.Column("id",              sa.Integer(),    primary_key=True),
        sa.Column("subscription_id", sa.Integer(),    sa.ForeignKey("subscriptions.id", ondelete="CASCADE"), nullable=False),
        sa.Column("event_type",      sa.String(100),  nullable=False),
        sa.Column("amount_usd",      sa.Float(),      nullable=True),
        sa.Column("mp_payment_id",   sa.String(255),  nullable=True),
        sa.Column("mp_status",       sa.String(100),  nullable=True),
        sa.Column("mp_detail",       sa.Text(),       nullable=True),
        sa.Column("notes",           sa.Text(),       nullable=True),
        sa.Column("created_at",      sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
    )
    op.create_index("ix_billing_events_subscription_id", "billing_events", ["subscription_id"])
    op.create_index("ix_billing_events_mp_payment_id",   "billing_events", ["mp_payment_id"])

    # ── blocked_admin_emails ───────────────────────────────────────────────────
    op.create_table(
        "blocked_admin_emails",
        sa.Column("id",            sa.Integer(),    primary_key=True),
        sa.Column("email",         sa.String(255),  nullable=False, unique=True),
        sa.Column("reason",        sa.Text(),       nullable=True),
        sa.Column("blocked_at",    sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("unblock_after", sa.DateTime(timezone=True), nullable=True),
        sa.Column("is_active",     sa.Boolean(),   nullable=False, server_default="true"),
    )
    op.create_index("ix_blocked_admin_emails_email",     "blocked_admin_emails", ["email"])


def downgrade() -> None:
    op.drop_table("blocked_admin_emails")
    op.drop_table("billing_events")
    op.drop_table("subscriptions")
