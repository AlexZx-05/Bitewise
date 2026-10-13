"""Persist the selected-goal insight with each scan.

Revision ID: 0004_scan_goal_insight
Revises: 0003_packaged_scans
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0004_scan_goal_insight"
down_revision: Union[str, None] = "0003_packaged_scans"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "packaged_scan_details",
        sa.Column("goal_insight", sa.String(length=1000), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("packaged_scan_details", "goal_insight")
