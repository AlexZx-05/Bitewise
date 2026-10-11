"""Add validated wellness goal to user profiles.

Revision ID: 0002_profile_goal
Revises: 0001_initial
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0002_profile_goal"
down_revision: Union[str, None] = "0001_initial"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("user_profiles", sa.Column("goal", sa.String(length=30), nullable=True))
    op.create_check_constraint(
        "ck_user_profiles_goal",
        "user_profiles",
        "goal IS NULL OR goal IN ('fat_loss', 'muscle_gain', 'maintenance')",
    )


def downgrade() -> None:
    op.drop_constraint("ck_user_profiles_goal", "user_profiles", type_="check")
    op.drop_column("user_profiles", "goal")
