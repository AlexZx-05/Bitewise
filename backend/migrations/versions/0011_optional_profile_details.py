"""Add optional onboarding profile details.

Revision ID: 0011_optional_profile_details
Revises: 0010_alternative_products
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa

revision: str = "0011_optional_profile_details"
down_revision: Union[str, None] = "0010_alternative_products"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("user_profiles", sa.Column("age", sa.Integer(), nullable=True))
    op.add_column(
        "user_profiles",
        sa.Column("gender", sa.String(length=30), nullable=True),
    )
    op.add_column(
        "user_profiles",
        sa.Column("height_cm", sa.Numeric(5, 2), nullable=True),
    )
    op.add_column(
        "user_profiles",
        sa.Column("weight_kg", sa.Numeric(6, 2), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("user_profiles", "weight_kg")
    op.drop_column("user_profiles", "height_cm")
    op.drop_column("user_profiles", "gender")
    op.drop_column("user_profiles", "age")
