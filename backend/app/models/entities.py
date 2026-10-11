from datetime import datetime
from decimal import Decimal
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    Numeric,
    String,
    Table,
    Column,
    Uuid,
    func,
)
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.db.base import Base

product_ingredients = Table(
    "product_ingredients",
    Base.metadata,
    Column(
        "product_id",
        Uuid(as_uuid=True),
        ForeignKey("food_products.id", ondelete="CASCADE"),
        primary_key=True,
    ),
    Column(
        "ingredient_id",
        Uuid(as_uuid=True),
        ForeignKey("ingredients.id", ondelete="CASCADE"),
        primary_key=True,
    ),
)


class UserProfile(Base):
    __tablename__ = "user_profiles"

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    display_name: Mapped[Optional[str]] = mapped_column(String(100))
    daily_calorie_goal: Mapped[Optional[int]] = mapped_column(Integer)
    daily_protein_goal_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    daily_carbohydrate_goal_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    daily_fat_goal_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Ingredient(Base):
    __tablename__ = "ingredients"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(200), unique=True, index=True)
    products: Mapped[list["FoodProduct"]] = relationship(
        secondary=product_ingredients, back_populates="ingredients"
    )


class FoodProduct(Base):
    __tablename__ = "food_products"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    name: Mapped[str] = mapped_column(String(200), index=True)
    brand: Mapped[Optional[str]] = mapped_column(String(150))
    barcode: Mapped[Optional[str]] = mapped_column(String(64), unique=True, index=True)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    ingredients: Mapped[list[Ingredient]] = relationship(
        secondary=product_ingredients, back_populates="products"
    )


class FoodScan(Base):
    __tablename__ = "food_scans"
    __table_args__ = (
        CheckConstraint(
            "status IN ('pending', 'completed', 'failed')", name="ck_food_scans_status"
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    profile_id: Mapped[str] = mapped_column(
        ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )
    product_id: Mapped[Optional[UUID]] = mapped_column(
        ForeignKey("food_products.id", ondelete="SET NULL")
    )
    status: Mapped[str] = mapped_column(String(20), default="pending")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )
    findings: Mapped[list["ScanFinding"]] = relationship(
        back_populates="scan", cascade="all, delete-orphan"
    )


class ScanFinding(Base):
    __tablename__ = "scan_findings"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    scan_id: Mapped[UUID] = mapped_column(
        ForeignKey("food_scans.id", ondelete="CASCADE"), index=True
    )
    category: Mapped[str] = mapped_column(String(100))
    label: Mapped[str] = mapped_column(String(200))
    details: Mapped[Optional[str]] = mapped_column(String(1000))
    scan: Mapped[FoodScan] = relationship(back_populates="findings")


class DiaryEntry(Base):
    __tablename__ = "diary_entries"

    id: Mapped[UUID] = mapped_column(Uuid(as_uuid=True), primary_key=True, default=uuid4)
    profile_id: Mapped[str] = mapped_column(
        ForeignKey("user_profiles.id", ondelete="CASCADE"), index=True
    )
    product_id: Mapped[Optional[UUID]] = mapped_column(
        ForeignKey("food_products.id", ondelete="SET NULL")
    )
    scan_id: Mapped[Optional[UUID]] = mapped_column(
        ForeignKey("food_scans.id", ondelete="SET NULL")
    )
    serving_size_grams: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    consumed_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), index=True
    )
