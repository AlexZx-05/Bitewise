"""Store confirmed packaged-label scans and findings.

Revision ID: 0003_packaged_scans
Revises: 0002_profile_goal
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0003_packaged_scans"
down_revision: Union[str, None] = "0002_profile_goal"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "packaged_scan_details",
        sa.Column("scan_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("product_name", sa.String(length=200), nullable=False),
        sa.Column("brand", sa.String(length=150), nullable=True),
        sa.Column("serving_size_g", sa.Numeric(8, 2), nullable=False),
        sa.Column("nutrition_basis", sa.String(length=20), nullable=False),
        sa.Column("energy_kcal", sa.Numeric(9, 2), nullable=True),
        sa.Column("protein_g", sa.Numeric(8, 2), nullable=True),
        sa.Column("carbohydrates_g", sa.Numeric(8, 2), nullable=True),
        sa.Column("total_fat_g", sa.Numeric(8, 2), nullable=True),
        sa.Column("sodium_mg", sa.Numeric(9, 2), nullable=True),
        sa.Column("ingredients", sa.JSON(), nullable=False),
        sa.Column("precautionary_allergen_statement", sa.String(length=1000), nullable=True),
        sa.ForeignKeyConstraint(["scan_id"], ["food_scans.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("scan_id"),
        sa.CheckConstraint(
            "nutrition_basis IN ('per_serving', 'per_100g')",
            name="ck_packaged_scan_details_nutrition_basis",
        ),
    )


def downgrade() -> None:
    op.drop_table("packaged_scan_details")
