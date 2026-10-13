"""Store the generated explanation for confirmed packaged-food scans.

Revision ID: 0005_packaged_llm_explanation
Revises: 0004_scan_goal_insight
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0005_packaged_llm_explanation"
down_revision: Union[str, None] = "0004_scan_goal_insight"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column(
        "packaged_scan_details",
        sa.Column("llm_explanation", sa.String(length=2000), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("packaged_scan_details", "llm_explanation")
