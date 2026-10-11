"""Create the initial FoodScan data model.

Revision ID: 0001_initial
Revises:
"""
from typing import Sequence, Union

from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision: str = "0001_initial"
down_revision: Union[str, None] = None
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.create_table(
        "user_profiles",
        sa.Column("id", sa.String(length=36), nullable=False),
        sa.Column("display_name", sa.String(length=100), nullable=True),
        sa.Column("daily_calorie_goal", sa.Integer(), nullable=True),
        sa.Column("daily_protein_goal_g", sa.Numeric(8, 2), nullable=True),
        sa.Column("daily_carbohydrate_goal_g", sa.Numeric(8, 2), nullable=True),
        sa.Column("daily_fat_goal_g", sa.Numeric(8, 2), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_table(
        "food_products",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.Column("brand", sa.String(length=150), nullable=True),
        sa.Column("barcode", sa.String(length=64), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("barcode"),
    )
    op.create_index(op.f("ix_food_products_barcode"), "food_products", ["barcode"], unique=True)
    op.create_index(op.f("ix_food_products_name"), "food_products", ["name"], unique=False)
    op.create_table(
        "ingredients",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("name", sa.String(length=200), nullable=False),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("name"),
    )
    op.create_index(op.f("ix_ingredients_name"), "ingredients", ["name"], unique=True)
    op.create_table(
        "product_ingredients",
        sa.Column("product_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("ingredient_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(
            ["ingredient_id"], ["ingredients.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(
            ["product_id"], ["food_products.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("product_id", "ingredient_id"),
    )
    op.create_table(
        "food_scans",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("profile_id", sa.String(length=36), nullable=False),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("status", sa.String(length=20), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.CheckConstraint(
            "status IN ('pending', 'completed', 'failed')", name="ck_food_scans_status"
        ),
        sa.ForeignKeyConstraint(
            ["product_id"], ["food_products.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"], ["user_profiles.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_food_scans_profile_id"), "food_scans", ["profile_id"], unique=False)
    op.create_table(
        "scan_findings",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("scan_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("category", sa.String(length=100), nullable=False),
        sa.Column("label", sa.String(length=200), nullable=False),
        sa.Column("details", sa.String(length=1000), nullable=True),
        sa.ForeignKeyConstraint(["scan_id"], ["food_scans.id"], ondelete="CASCADE"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_scan_findings_scan_id"), "scan_findings", ["scan_id"], unique=False)
    op.create_table(
        "diary_entries",
        sa.Column("id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column("profile_id", sa.String(length=36), nullable=False),
        sa.Column("product_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("scan_id", postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column("serving_size_grams", sa.Numeric(8, 2), nullable=True),
        sa.Column(
            "consumed_at", sa.DateTime(timezone=True), server_default=sa.text("now()"), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ["product_id"], ["food_products.id"], ondelete="SET NULL"
        ),
        sa.ForeignKeyConstraint(
            ["profile_id"], ["user_profiles.id"], ondelete="CASCADE"
        ),
        sa.ForeignKeyConstraint(["scan_id"], ["food_scans.id"], ondelete="SET NULL"),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(op.f("ix_diary_entries_consumed_at"), "diary_entries", ["consumed_at"], unique=False)
    op.create_index(op.f("ix_diary_entries_profile_id"), "diary_entries", ["profile_id"], unique=False)


def downgrade() -> None:
    op.drop_index(op.f("ix_diary_entries_profile_id"), table_name="diary_entries")
    op.drop_index(op.f("ix_diary_entries_consumed_at"), table_name="diary_entries")
    op.drop_table("diary_entries")
    op.drop_index(op.f("ix_scan_findings_scan_id"), table_name="scan_findings")
    op.drop_table("scan_findings")
    op.drop_index(op.f("ix_food_scans_profile_id"), table_name="food_scans")
    op.drop_table("food_scans")
    op.drop_table("product_ingredients")
    op.drop_index(op.f("ix_ingredients_name"), table_name="ingredients")
    op.drop_table("ingredients")
    op.drop_index(op.f("ix_food_products_name"), table_name="food_products")
    op.drop_index(op.f("ix_food_products_barcode"), table_name="food_products")
    op.drop_table("food_products")
    op.drop_table("user_profiles")
