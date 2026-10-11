from fastapi import APIRouter

from app.api.v1.routes import products, profiles

api_router = APIRouter()
api_router.include_router(profiles.router, tags=["profile"])
api_router.include_router(products.router, tags=["products"])
