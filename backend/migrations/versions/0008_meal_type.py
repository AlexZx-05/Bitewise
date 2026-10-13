"""Add meal type to saved meal analyses.

Revision ID: 0008_meal_type
Revises: 0007_meal_scans
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0008_meal_type"
down_revision: Union[str, None] = "0007_meal_scans"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "meal_scan_details",
        sa.Column(
            "meal_type",
            sa.String(length=20),
            nullable=False,
            server_default="snack",
        ),
    )


def downgrade() -> None:
    op.drop_column("meal_scan_details", "meal_type")
