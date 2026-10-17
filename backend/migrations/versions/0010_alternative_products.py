"""Store product cards for goal-based alternatives.

Revision ID: 0010_alternative_products
Revises: 0009_goal_alternatives
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0010_alternative_products"
down_revision: Union[str, None] = "0009_goal_alternatives"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "packaged_scan_details",
        sa.Column("alternative_product", sa.JSON(), nullable=True),
    )
    op.add_column(
        "meal_scan_details",
        sa.Column("alternative_product", sa.JSON(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("meal_scan_details", "alternative_product")
    op.drop_column("packaged_scan_details", "alternative_product")
