from fastapi import APIRouter

from app.api.v1.routes import meals, products, profiles, scans

api_router = APIRouter()
api_router.include_router(profiles.router, tags=["profile"])
api_router.include_router(products.router, tags=["products"])
api_router.include_router(scans.router, tags=["scans"])
api_router.include_router(meals.router, tags=["meals"])
