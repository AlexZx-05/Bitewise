"""Persist separately declared allergens from packaged labels.

Revision ID: 0006_declared_allergens
Revises: 0005_packaged_llm_explanation
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0006_declared_allergens"
down_revision: Union[str, None] = "0005_packaged_llm_explanation"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "packaged_scan_details",
        sa.Column("declared_allergens", sa.JSON(), nullable=False, server_default="[]"),
    )
    op.alter_column("packaged_scan_details", "declared_allergens", server_default=None)


def downgrade() -> None:
    op.drop_column("packaged_scan_details", "declared_allergens")
