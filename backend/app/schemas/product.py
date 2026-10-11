from typing import Optional
from uuid import UUID

from pydantic import BaseModel, ConfigDict


class ProductRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    brand: Optional[str]
    barcode: Optional[str]
    ingredients: list[str]
