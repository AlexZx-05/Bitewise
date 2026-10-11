from datetime import datetime
from decimal import Decimal
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field


class ProfileUpdate(BaseModel):
    display_name: Optional[str] = Field(default=None, max_length=100)
    daily_calorie_goal: Optional[int] = Field(default=None, ge=0, le=10000)
    daily_protein_goal_g: Optional[Decimal] = Field(default=None, ge=0, le=1000)
    daily_carbohydrate_goal_g: Optional[Decimal] = Field(default=None, ge=0, le=2000)
    daily_fat_goal_g: Optional[Decimal] = Field(default=None, ge=0, le=1000)


class ProfileRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    display_name: Optional[str]
    daily_calorie_goal: Optional[int]
    daily_protein_goal_g: Optional[Decimal]
    daily_carbohydrate_goal_g: Optional[Decimal]
    daily_fat_goal_g: Optional[Decimal]
    created_at: datetime
    updated_at: datetime
