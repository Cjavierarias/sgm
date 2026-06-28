"""add company_id to invoices

Revision ID: d4e5f6a7b8c9
Revises: c3d4e5f6a7b8
Create Date: 2026-06-28

Correcciones de seguridad multi-tenant:
  - Agrega company_id a la tabla invoices
  - Actualiza invoice existentes con company_id desde su purchase_order
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

revision = "d4e5f6a7b8c9"
down_revision = "c3d4e5f6a7b8"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Agregar company_id nullable primero
    op.add_column("invoices", sa.Column("company_id", sa.Integer(), sa.ForeignKey("companies.id", ondelete="CASCADE"), nullable=True, index=True))

    # Poblar company_id desde la purchase_order relacionada
    op.execute("""
        UPDATE invoices
        SET company_id = po.company_id
        FROM purchase_orders po
        WHERE invoices.purchase_order_id = po.id
    """)

    # Hacer company_id NOT NULL
    op.alter_column("invoices", "company_id", nullable=False)


def downgrade() -> None:
    op.drop_column("invoices", "company_id")
