import re
from datetime import datetime
from decimal import Decimal, InvalidOperation
from typing import Any, Literal, Optional
from uuid import UUID

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

NutritionBasis = Literal["per_serving", "per_100g"]


class PackagedScanCreate(BaseModel):
    model_config = ConfigDict(extra="forbid")

    product_name: str = Field(min_length=1, max_length=200)
    brand: Optional[str] = Field(default=None, max_length=150)
    serving_size_g: Decimal = Field(gt=0, le=10000)
    nutrition_basis: NutritionBasis
    energy_kcal: Optional[Decimal] = Field(default=None, ge=0, le=100000)
    protein_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    carbohydrates_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    total_fat_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    sodium_mg: Optional[Decimal] = Field(default=None, ge=0, le=100000)
    ingredients: list[str] = Field(default_factory=list, max_length=200)
    declared_allergens: list[str] = Field(default_factory=list, max_length=50)
    precautionary_allergen_statement: Optional[str] = Field(
        default=None, max_length=1000
    )

    @field_validator("product_name", "brand", "precautionary_allergen_statement")
    @classmethod
    def strip_optional_text(cls, value: Optional[str]) -> Optional[str]:
        if value is None:
            return None
        return value.strip() or None

    @field_validator("ingredients")
    @classmethod
    def clean_ingredients(cls, values: list[str]) -> list[str]:
        cleaned = [value.strip() for value in values if value.strip()]
        if any(len(value) > 200 for value in cleaned):
            raise ValueError("Each ingredient must be 200 characters or fewer.")
        return cleaned

    @field_validator("declared_allergens")
    @classmethod
    def clean_declared_allergens(cls, values: list[str]) -> list[str]:
        return [value.strip() for value in values if value.strip()]

    @model_validator(mode="after")
    def require_nutrition_value(self) -> "PackagedScanCreate":
        if all(
            value is None
            for value in (
                self.energy_kcal,
                self.protein_g,
                self.carbohydrates_g,
                self.total_fat_g,
                self.sodium_mg,
            )
        ):
            raise ValueError("Enter at least one nutrition value from the label.")
        if not self.product_name:
            raise ValueError("Product name cannot be blank.")
        return self


class PackagedScanDetailsRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    product_name: str
    brand: Optional[str]
    serving_size_g: Decimal
    nutrition_basis: NutritionBasis
    energy_kcal: Optional[Decimal]
    protein_g: Optional[Decimal]
    carbohydrates_g: Optional[Decimal]
    total_fat_g: Optional[Decimal]
    sodium_mg: Optional[Decimal]
    ingredients: list[str]
    declared_allergens: list[str] = Field(default_factory=list)
    precautionary_allergen_statement: Optional[str]
    llm_explanation: Optional[str] = None


class ScanFindingRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    category: str
    label: str
    details: Optional[str]


class PackagedScanRead(BaseModel):
    scan_id: UUID
    status: str
    created_at: datetime
    product: PackagedScanDetailsRead
    findings: list[ScanFindingRead]
    goal_insight: str
    llm_explanation: Optional[str] = None


class NutritionExtraction(BaseModel):
    energy_kcal: Optional[Decimal] = Field(default=None, ge=0, le=100000)
    protein_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    carbohydrates_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    total_fat_g: Optional[Decimal] = Field(default=None, ge=0, le=10000)
    sodium_mg: Optional[Decimal] = Field(default=None, ge=0, le=100000)


class PackagedLabelExtraction(BaseModel):
    product_name: Optional[str] = Field(default=None, max_length=200)
    brand: Optional[str] = Field(default=None, max_length=150)
    serving_size_g: Optional[Decimal] = Field(default=None, gt=0, le=10000)
    nutrition_basis: Optional[NutritionBasis] = None
    nutrition: NutritionExtraction = Field(default_factory=NutritionExtraction)
    ingredients: list[str] = Field(default_factory=list, max_length=200)
    declared_allergens: list[str] = Field(default_factory=list, max_length=50)
    allergens: list[str] = Field(default_factory=list, max_length=50)
    precautionary_allergen_statement: Optional[str] = Field(
        default=None, max_length=1000
    )
    missing_fields: list[str] = Field(default_factory=list, max_length=30)
    uncertain_fields: list[str] = Field(default_factory=list, max_length=30)
    extraction_note: str = Field(
        default="Review all extracted values against the package.", max_length=500
    )

    @field_validator(
        "ingredients",
        "declared_allergens",
        "allergens",
        "missing_fields",
        "uncertain_fields",
        mode="before",
    )
    @classmethod
    def empty_null_lists(cls, value: object) -> object:
        return [] if value is None else value

    @model_validator(mode="before")
    @classmethod
    def normalize_vision_response(cls, value: Any) -> Any:
        if not isinstance(value, dict):
            return value

        data = value.copy()
        for alias, canonical in (
            ("name", "product_name"),
            ("serving_size", "serving_size_g"),
            ("allergen_list", "declared_allergens"),
            ("precautionary_statement", "precautionary_allergen_statement"),
        ):
            if canonical not in data and alias in data:
                data[canonical] = data[alias]

        nutrition = data.get("nutrition")
        nutrition_was_invalid = nutrition is not None and not isinstance(
            nutrition,
            dict,
        )
        if nutrition is None:
            nutrition = {}
        if not isinstance(nutrition, dict):
            nutrition = {}
            data["nutrition"] = nutrition

        nutrition = nutrition.copy()
        nutrient_fields = (
            "energy_kcal",
            "protein_g",
            "carbohydrates_g",
            "total_fat_g",
            "sodium_mg",
        )
        if isinstance(data.get("serving_size_g"), str):
            serving_size = re.fullmatch(
                r"\s*(\d+(?:\.\d+)?)\s*(?:g|grams?)?\s*",
                data["serving_size_g"],
                flags=re.IGNORECASE,
            )
            if serving_size:
                data["serving_size_g"] = serving_size.group(1)
        uncertain = data.get("uncertain_fields")
        missing = data.get("missing_fields")
        uncertain_fields = list(uncertain) if isinstance(uncertain, list) else []
        missing_fields = list(missing) if isinstance(missing, list) else []

        for field in nutrient_fields:
            if field not in nutrition and field in data:
                nutrition[field] = data[field]
            number = nutrition.get(field)
            if isinstance(number, str):
                try:
                    number = Decimal(number.strip().replace(",", ""))
                    if not number.is_finite():
                        raise InvalidOperation
                    nutrition[field] = number
                except InvalidOperation:
                    nutrition[field] = None
                    if field not in uncertain_fields:
                        uncertain_fields.append(field)
                    if field not in missing_fields:
                        missing_fields.append(field)
            elif number is not None and (
                isinstance(number, bool)
                or not isinstance(number, (int, float, Decimal))
                or isinstance(number, float) and not Decimal(str(number)).is_finite()
                or isinstance(number, Decimal) and not number.is_finite()
            ):
                nutrition[field] = None
                if field not in uncertain_fields:
                    uncertain_fields.append(field)
                if field not in missing_fields:
                    missing_fields.append(field)

        if nutrition_was_invalid:
            for field in nutrient_fields:
                if field not in uncertain_fields:
                    uncertain_fields.append(field)
                if field not in missing_fields:
                    missing_fields.append(field)

        data["nutrition"] = nutrition
        data["uncertain_fields"] = uncertain_fields
        data["missing_fields"] = missing_fields

        list_fields = (
            "ingredients",
            "declared_allergens",
            "allergens",
            "missing_fields",
            "uncertain_fields",
        )
        for field in list_fields:
            field_value = data.get(field)
            if field_value is None:
                data[field] = []
            elif isinstance(field_value, str):
                data[field] = [field_value.strip()] if field_value.strip() else []
            elif isinstance(field_value, list):
                if any(not isinstance(item, str) for item in field_value):
                    if field not in uncertain_fields:
                        uncertain_fields.append(field)
                data[field] = [
                    item.strip()
                    for item in field_value
                    if isinstance(item, str) and item.strip()
                ]

        if not data.get("declared_allergens") and data.get("allergens"):
            data["declared_allergens"] = data["allergens"]
        if data.get("extraction_note") is None:
            data["extraction_note"] = (
                "Review all extracted values against the package."
            )
        elif not isinstance(data.get("extraction_note"), str) or len(
            data["extraction_note"]
        ) > 500:
            data["extraction_note"] = (
                "Some extracted details could not be read. Review the label."
            )

        basis = data.get("nutrition_basis")
        if isinstance(basis, str):
            normalized_basis = basis.lower().replace(" ", "").replace("_", "")
            if normalized_basis in {"per100g", "100g"}:
                data["nutrition_basis"] = "per_100g"
            elif normalized_basis in {"perserving", "serving"}:
                data["nutrition_basis"] = "per_serving"
            elif basis not in {"per_100g", "per_serving"}:
                data["nutrition_basis"] = None
                if "nutrition_basis" not in uncertain_fields:
                    uncertain_fields.append("nutrition_basis")
                if "nutrition_basis" not in missing_fields:
                    missing_fields.append("nutrition_basis")

        for field in ("product_name", "brand", "precautionary_allergen_statement"):
            if data.get(field) is not None and not isinstance(data[field], str):
                data[field] = None
                if field not in uncertain_fields:
                    uncertain_fields.append(field)

        return data


class PackagedLabelExtractionResponse(BaseModel):
    extracted: PackagedLabelExtraction
