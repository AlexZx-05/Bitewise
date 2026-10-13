from datetime import date, datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, Field, field_validator, model_validator


class MealComponentSuggestion(BaseModel):
    food_name: str = Field(min_length=1, max_length=200)
    estimated_portion_g: Optional[Decimal] = Field(default=None, gt=0, le=5000)
    possible_ingredients: list[str] = Field(default_factory=list, max_length=50)
    suggested_cooking_method: Optional[str] = Field(default=None, max_length=200)
    uncertain_fields: list[str] = Field(default_factory=list, max_length=20)


class MealVisionExtraction(BaseModel):
    meal_name: str = Field(min_length=1, max_length=200)
    components: list[MealComponentSuggestion] = Field(min_length=1, max_length=10)
    uncertain_fields: list[str] = Field(default_factory=list, max_length=20)
    extraction_note: str = Field(
        default="Review all suggestions before confirming the meal.",
        max_length=500,
    )

    @model_validator(mode="before")
    @classmethod
    def normalize_vision_response(cls, value):
        if not isinstance(value, dict):
            return value

        data = value.copy()
        for wrapper in ("extracted", "meal", "result"):
            if isinstance(data.get(wrapper), dict):
                data = data[wrapper].copy()
                break

        meal_name = data.get("meal_name")
        if not isinstance(meal_name, str) or not meal_name.strip():
            meal_name = next(
                (
                    data[alias].strip()
                    for alias in ("dish_name", "name")
                    if isinstance(data.get(alias), str) and data[alias].strip()
                ),
                None,
            )
            if meal_name is None:
                raw_components = data.get("components")
                if isinstance(raw_components, dict):
                    raw_components = raw_components.get("items", [])
                component_names = []
                if isinstance(raw_components, list):
                    for component in raw_components:
                        if isinstance(component, str) and component.strip():
                            component_names.append(component.strip())
                        elif isinstance(component, dict):
                            name = next(
                                (
                                    component[key].strip()
                                    for key in ("food_name", "name", "item", "dish")
                                    if isinstance(component.get(key), str)
                                    and component[key].strip()
                                ),
                                None,
                            )
                            if name:
                                component_names.append(name)
                meal_name = (
                    " and ".join(component_names[:3])
                    if component_names
                    else "Meal to review"
                )
            uncertain_fields = data.get("uncertain_fields")
            if isinstance(uncertain_fields, list):
                data["uncertain_fields"] = list(uncertain_fields)
            else:
                data["uncertain_fields"] = []
            if "meal_name" not in data["uncertain_fields"]:
                data["uncertain_fields"].append("meal_name")
            data["meal_name"] = meal_name[:200]
        if isinstance(data.get("components"), dict):
            components = data["components"]
            data["components"] = components.get("items", [])
        elif data.get("components") is None:
            data["components"] = []
        components = data.get("components")
        if isinstance(components, list):
            normalized = []
            for component in components:
                if isinstance(component, str):
                    normalized.append({"food_name": component})
                    continue
                if not isinstance(component, dict):
                    continue
                item = component.copy()
                if "food_name" not in item:
                    for alias in ("name", "item", "dish"):
                        if isinstance(item.get(alias), str):
                            item["food_name"] = item[alias]
                            break
                for list_field in ("possible_ingredients", "uncertain_fields"):
                    field_value = item.get(list_field)
                    if isinstance(field_value, str):
                        item[list_field] = [field_value] if field_value.strip() else []
                    elif field_value is None:
                        item[list_field] = []
                normalized.append(item)
            data["components"] = normalized

        if isinstance(data.get("uncertain_fields"), str):
            data["uncertain_fields"] = [data["uncertain_fields"]]
        elif data.get("uncertain_fields") is None:
            data["uncertain_fields"] = []
        if not isinstance(data.get("extraction_note"), str):
            data["extraction_note"] = (
                "Review all suggestions before confirming the meal."
            )
        return data


class MealVisionExtractionResponse(BaseModel):
    extracted: MealVisionExtraction


class UsdaFoodCandidate(BaseModel):
    fdc_id: int
    description: str
    data_type: Optional[str] = None


class UsdaFoodSearchResponse(BaseModel):
    foods: list[UsdaFoodCandidate]


class ConfirmedMealComponent(BaseModel):
    fdc_id: int = Field(gt=0)
    food_name: str = Field(min_length=1, max_length=200)
    portion_g: Decimal = Field(gt=0, le=5000)
    portion_pieces: Optional[Decimal] = Field(default=None, gt=0, le=100)
    grams_per_piece: Optional[Decimal] = Field(default=None, gt=0, le=5000)
    ingredients: list[str] = Field(default_factory=list, max_length=50)
    cooking_method: str = Field(min_length=1, max_length=200)

    @model_validator(mode="after")
    def validate_piece_portion(self):
        if (self.portion_pieces is None) != (self.grams_per_piece is None):
            raise ValueError(
                "Specify both the number of pieces and grams per piece."
            )
        if (
            self.portion_pieces is not None
            and self.grams_per_piece is not None
            and self.portion_pieces * self.grams_per_piece != self.portion_g
        ):
            raise ValueError("Piece count and weight must match the total portion.")
        return self

    @field_validator("food_name", "cooking_method")
    @classmethod
    def strip_text(cls, value: str) -> str:
        return value.strip()


class MealScanConfirm(BaseModel):
    meal_name: str = Field(min_length=1, max_length=200)
    meal_type: str = Field(
        default="snack", pattern="^(breakfast|lunch|dinner|snack)$"
    )
    components: list[ConfirmedMealComponent] = Field(min_length=1, max_length=10)

    @field_validator("meal_name")
    @classmethod
    def strip_meal_name(cls, value: str) -> str:
        return value.strip()


class MealComponentRead(BaseModel):
    food_name: str
    portion_g: Decimal
    portion_pieces: Optional[Decimal] = None
    grams_per_piece: Optional[Decimal] = None
    ingredients: list[str]
    cooking_method: str
    fdc_id: int
    data_source: str
    nutrition: dict[str, Decimal]


class MealScanRead(BaseModel):
    scan_id: str
    status: str
    meal_type: str
    created_at: datetime
    meal_name: str
    components: list[MealComponentRead]
    nutrition_totals: dict[str, Decimal]
    goal_explanation: str
    alternative_guidance: str


class MealDiaryRead(BaseModel):
    date: date
    meals: list[MealScanRead]
