import asyncio
from decimal import Decimal
from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, HTTPException, Query, UploadFile, status
from sqlalchemy.orm import Session, selectinload

from app.api.v1.routes.profiles import LOCAL_PROFILE_ID
from app.db.session import get_db
from app.models import FoodScan, MealScanDetails, UserProfile
from app.schemas.meal import (
    MealScanConfirm,
    MealScanRead,
    MealVisionExtractionResponse,
    UsdaFoodSearchResponse,
)
from app.services.groq import (
    GroqServiceError,
    explain_meal,
    extract_meal,
)
from app.services.usda import UsdaServiceError, get_food_nutrition, search_foods

router = APIRouter()
_MAX_IMAGE_BYTES = 8 * 1024 * 1024
_NUTRIENTS = ("energy_kcal", "protein_g", "carbohydrates_g", "total_fat_g", "sodium_mg")


@router.post(
    "/scans/meals/extract",
    response_model=MealVisionExtractionResponse,
)
async def extract_meal_from_photo(
    image: UploadFile = File(...),
) -> MealVisionExtractionResponse:
    if image.content_type not in {"image/jpeg", "image/png"}:
        raise HTTPException(
            status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            detail="Use a JPEG or PNG meal photo.",
        )
    content = await image.read(_MAX_IMAGE_BYTES + 1)
    if len(content) > _MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
            detail="The meal photo must be 8 MB or smaller.",
        )
    try:
        extracted = await extract_meal(image.content_type, content)
    except GroqServiceError as error:
        raise HTTPException(
            status_code=error.status_code,
            detail=f"Groq meal identification failed: {error}",
        ) from error
    return MealVisionExtractionResponse(extracted=extracted)


@router.get("/scans/meals/usda-search", response_model=UsdaFoodSearchResponse)
async def search_usda_foods(
    query: str = Query(min_length=2, max_length=120),
) -> UsdaFoodSearchResponse:
    try:
        foods = await search_foods(query.strip())
    except UsdaServiceError as error:
        raise HTTPException(status_code=error.status_code, detail=str(error)) from error
    return UsdaFoodSearchResponse(foods=foods)


@router.post(
    "/scans/meals/confirm",
    response_model=MealScanRead,
    status_code=status.HTTP_201_CREATED,
)
async def confirm_meal(
    request: MealScanConfirm,
    db: Session = Depends(get_db),
) -> MealScanRead:
    try:
        unique_food_ids = {item.fdc_id for item in request.components}
        food_details = await asyncio.gather(
            *(get_food_nutrition(fdc_id) for fdc_id in unique_food_ids)
        )
        nutrition_by_id = {
            details["fdc_id"]: details for details in food_details
        }
    except UsdaServiceError as error:
        raise HTTPException(status_code=error.status_code, detail=str(error)) from error

    components: list[dict[str, object]] = []
    for item in request.components:
        food = nutrition_by_id[item.fdc_id]
        nutrition_per_100g = food["nutrition_per_100g"]
        portion_factor = item.portion_g / Decimal("100")
        portion_nutrition = {
            name: str(
                (
                    Decimal(str(nutrition_per_100g[name]))
                    * portion_factor
                ).quantize(Decimal("0.1"))
            )
            for name in _NUTRIENTS
            if name in nutrition_per_100g
        }
        components.append(
            {
                "food_name": item.food_name,
                "portion_g": str(item.portion_g),
                "ingredients": item.ingredients,
                "cooking_method": item.cooking_method,
                "fdc_id": item.fdc_id,
                "data_source": f"USDA FoodData Central ({food['data_type']})",
                "nutrition": portion_nutrition,
            }
        )

    totals: dict[str, Decimal] = {}
    for name in _NUTRIENTS:
        if all(name in item["nutrition"] for item in components):
            totals[name] = sum(
                (Decimal(item["nutrition"][name]) for item in components),
                start=Decimal("0"),
            ).quantize(Decimal("0.1"))

    profile = db.get(UserProfile, LOCAL_PROFILE_ID)
    if profile is None:
        profile = UserProfile(id=LOCAL_PROFILE_ID)
        db.add(profile)
        db.flush()
    try:
        explanation = await explain_meal(
            request.meal_name,
            components,
            totals,
            profile.goal,
            profile.daily_calorie_goal,
        )
    except GroqServiceError as error:
        db.rollback()
        raise HTTPException(
            status_code=error.status_code,
            detail=f"Groq meal explanation failed: {error}",
        ) from error

    scan = FoodScan(id=uuid4(), profile_id=profile.id, status="completed")
    details = MealScanDetails(
        scan_id=scan.id,
        meal_name=request.meal_name,
        components=components,
        nutrition_totals={name: str(value) for name, value in totals.items()},
        goal_explanation=explanation,
        alternative_guidance=(
            "For a similar taste, compare a user-confirmed alternative with "
            "matching USDA FoodData Central records and the same portion size. "
            "No unverified alternative nutrition has been assumed."
        ),
    )
    db.add(scan)
    db.add(details)
    db.commit()
    persisted = _load_meal_scan(db, scan.id)
    if persisted is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The saved meal scan could not be reloaded.",
        )
    return _meal_response(persisted)


@router.get("/scans/meals/{scan_id}", response_model=MealScanRead)
def get_meal_scan(scan_id: UUID, db: Session = Depends(get_db)) -> MealScanRead:
    scan = _load_meal_scan(db, scan_id)
    if scan is None or scan.profile_id != LOCAL_PROFILE_ID:
        raise HTTPException(status_code=404, detail="Meal scan not found")
    return _meal_response(scan)


def _load_meal_scan(db: Session, scan_id: UUID) -> FoodScan | None:
    return (
        db.query(FoodScan)
        .options(
            selectinload(FoodScan.meal_details),
            selectinload(FoodScan.profile),
        )
        .filter(FoodScan.id == scan_id)
        .one_or_none()
    )


def _meal_response(scan: FoodScan) -> MealScanRead:
    details = scan.meal_details
    if details is None:
        raise HTTPException(status_code=404, detail="Meal scan not found")
    return MealScanRead(
        scan_id=str(scan.id),
        status=scan.status,
        meal_name=details.meal_name,
        components=details.components,
        nutrition_totals=details.nutrition_totals,
        goal_explanation=details.goal_explanation,
        alternative_guidance=details.alternative_guidance,
    )
