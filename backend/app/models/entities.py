from datetime import datetime
from decimal import Decimal
from typing import Optional
from uuid import UUID, uuid4

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    ForeignKey,
    Integer,
    JSON,
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
    __table_args__ = (
        CheckConstraint(
            "goal IS NULL OR goal IN ('fat_loss', 'muscle_gain', 'maintenance')",
            name="ck_user_profiles_goal",
        ),
    )

    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    display_name: Mapped[Optional[str]] = mapped_column(String(100))
    goal: Mapped[Optional[str]] = mapped_column(String(30))
    age: Mapped[Optional[int]] = mapped_column(Integer)
    gender: Mapped[Optional[str]] = mapped_column(String(30))
    height_cm: Mapped[Optional[Decimal]] = mapped_column(Numeric(5, 2))
    weight_kg: Mapped[Optional[Decimal]] = mapped_column(Numeric(6, 2))
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
    profile: Mapped[UserProfile] = relationship()
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
    packaged_details: Mapped[Optional["PackagedScanDetails"]] = relationship(
        back_populates="scan", cascade="all, delete-orphan", uselist=False
    )
    meal_details: Mapped[Optional["MealScanDetails"]] = relationship(
        back_populates="scan", cascade="all, delete-orphan", uselist=False
    )


class PackagedScanDetails(Base):
    __tablename__ = "packaged_scan_details"
    __table_args__ = (
        CheckConstraint(
            "nutrition_basis IN ('per_serving', 'per_100g')",
            name="ck_packaged_scan_details_nutrition_basis",
        ),
    )

    scan_id: Mapped[UUID] = mapped_column(
        ForeignKey("food_scans.id", ondelete="CASCADE"), primary_key=True
    )
    product_name: Mapped[str] = mapped_column(String(200))
    brand: Mapped[Optional[str]] = mapped_column(String(150))
    serving_size_g: Mapped[Decimal] = mapped_column(Numeric(8, 2))
    nutrition_basis: Mapped[str] = mapped_column(String(20))
    goal_insight: Mapped[Optional[str]] = mapped_column(String(1000))
    llm_explanation: Mapped[Optional[str]] = mapped_column(String(2000))
    goal_alternative: Mapped[Optional[str]] = mapped_column(String(1000))
    alternative_product: Mapped[Optional[dict[str, object]]] = mapped_column(
        JSON, nullable=True
    )
    energy_kcal: Mapped[Optional[Decimal]] = mapped_column(Numeric(9, 2))
    protein_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    carbohydrates_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    total_fat_g: Mapped[Optional[Decimal]] = mapped_column(Numeric(8, 2))
    sodium_mg: Mapped[Optional[Decimal]] = mapped_column(Numeric(9, 2))
    ingredients: Mapped[list[str]] = mapped_column(JSON)
    declared_allergens: Mapped[list[str]] = mapped_column(JSON, default=list)
    precautionary_allergen_statement: Mapped[Optional[str]] = mapped_column(
        String(1000)
    )
    scan: Mapped[FoodScan] = relationship(back_populates="packaged_details")


class MealScanDetails(Base):
    __tablename__ = "meal_scan_details"

    scan_id: Mapped[UUID] = mapped_column(
        ForeignKey("food_scans.id", ondelete="CASCADE"), primary_key=True
    )
    meal_type: Mapped[str] = mapped_column(
        String(20), default="snack", server_default="snack"
    )
    meal_name: Mapped[str] = mapped_column(String(200))
    components: Mapped[list[dict[str, object]]] = mapped_column(JSON)
    nutrition_totals: Mapped[dict[str, object]] = mapped_column(JSON)
    goal_explanation: Mapped[str] = mapped_column(String(2000))
    alternative_guidance: Mapped[str] = mapped_column(String(1000))
    alternative_product: Mapped[Optional[dict[str, object]]] = mapped_column(
        JSON, nullable=True
    )
    scan: Mapped[FoodScan] = relationship(back_populates="meal_details")


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
