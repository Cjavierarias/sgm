"""add equipment_id and sector columns to spare_parts

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-06-24

Columnas nuevas en spare_parts:
  - equipment_id (FK -> equipments.id, nullable, ondelete=SET NULL)
  - sector (String(100), nullable)
"""
from __future__ import annotations

import sqlalchemy as sa
from alembic import op

# revision identifiers, used by Alembic.
revision = "c3d4e5f6a7b8"
down_revision = "b2c3d4e5f6a7"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column("spare_parts", sa.Column("equipment_id", sa.Integer(), nullable=True))
    op.add_column("spare_parts", sa.Column("sector", sa.String(length=100), nullable=True))
    op.create_index(
        op.f("ix_spare_parts_equipment_id"), "spare_parts", ["equipment_id"]
    )
    op.create_foreign_key(
        "fk_spare_parts_equipment_id",
        "spare_parts",
        "equipments",
        ["equipment_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_spare_parts_equipment_id", "spare_parts")
    op.drop_index(op.f("ix_spare_parts_equipment_id"), table_name="spare_parts")
    op.drop_column("spare_parts", "sector")
    op.drop_column("spare_parts", "equipment_id")
