"""Store goal-based food alternatives.

Revision ID: 0009_goal_alternatives
Revises: 0008_meal_type
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0009_goal_alternatives"
down_revision: Union[str, None] = "0008_meal_type"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "packaged_scan_details",
        sa.Column("goal_alternative", sa.String(length=1000), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("packaged_scan_details", "goal_alternative")
