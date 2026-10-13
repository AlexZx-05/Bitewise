"""Store confirmed meal analyses.

Revision ID: 0007_meal_scans
Revises: 0006_declared_allergens
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0007_meal_scans"
down_revision: Union[str, None] = "0006_declared_allergens"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "meal_scan_details",
        sa.Column("scan_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("meal_name", sa.String(length=200), nullable=False),
        sa.Column("components", sa.JSON(), nullable=False),
        sa.Column("nutrition_totals", sa.JSON(), nullable=False),
        sa.Column("goal_explanation", sa.String(length=2000), nullable=False),
        sa.Column("alternative_guidance", sa.String(length=1000), nullable=False),
        sa.ForeignKeyConstraint(["scan_id"], ["food_scans.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("scan_id"),
    )


def downgrade() -> None:
    op.drop_table("meal_scan_details")
