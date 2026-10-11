from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session, selectinload

from app.db.session import get_db
from app.models import FoodProduct
from app.schemas.product import ProductRead

router = APIRouter()


@router.get("/products/{product_id}", response_model=ProductRead)
def get_product(product_id: UUID, db: Session = Depends(get_db)) -> ProductRead:
    product = (
        db.query(FoodProduct)
        .options(selectinload(FoodProduct.ingredients))
        .filter(FoodProduct.id == product_id)
        .one_or_none()
    )
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")

    return ProductRead(
        id=product.id,
        name=product.name,
        brand=product.brand,
        barcode=product.barcode,
        ingredients=[ingredient.name for ingredient in product.ingredients],
    )
