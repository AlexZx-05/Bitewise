from uuid import UUID, uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile, status
from sqlalchemy.orm import Session, selectinload

from app.api.v1.routes.profiles import LOCAL_PROFILE_ID
from app.db.session import get_db
from app.models import FoodScan, PackagedScanDetails, UserProfile
from app.schemas.scan import (
    PackagedLabelExtractionResponse,
    PackagedScanCreate,
    PackagedScanRead,
)
from app.services.groq import (
    GroqServiceError,
    explain_packaged_label,
    extract_packaged_label,
)
from app.services.packaged_analysis import analyze_confirmed_label

router = APIRouter()


def _scan_response(scan: FoodScan) -> PackagedScanRead:
    details = scan.packaged_details
    if details is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Packaged scan details not found",
        )
    profile = scan.profile
    return PackagedScanRead(
        scan_id=scan.id,
        status=scan.status,
        created_at=scan.created_at,
        product=details,
        findings=scan.findings,
        goal_insight=details.goal_insight
        or "No goal-based insight was stored for this scan.",
        llm_explanation=details.llm_explanation,
    )


@router.post(
    "/scans/packaged/extract",
    response_model=PackagedLabelExtractionResponse,
)
async def extract_packaged_label_from_photos(
    files: list[UploadFile] = File(...),
) -> PackagedLabelExtractionResponse:
    if not files or len(files) > 3:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_ENTITY,
            detail="Upload between one and three clear package-label photos.",
        )

    images: list[tuple[str, bytes]] = []
    total_bytes = 0
    for image in files:
        if image.content_type not in {"image/jpeg", "image/png"}:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail="Use a JPEG or PNG label photo.",
            )
        content = await image.read(8 * 1024 * 1024 + 1)
        if len(content) > 8 * 1024 * 1024:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Each photo must be 8 MB or smaller.",
            )
        total_bytes += len(content)
        if total_bytes > 12 * 1024 * 1024:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail="Combined photo size must be 12 MB or smaller.",
            )
        images.append((image.content_type, content))

    try:
        extracted = await extract_packaged_label(images)
    except GroqServiceError as error:
        raise HTTPException(
            status_code=error.status_code,
            detail=f"Groq label extraction failed: {error}",
        ) from error
    return PackagedLabelExtractionResponse(extracted=extracted)


@router.post(
    "/scans/packaged",
    response_model=PackagedScanRead,
    status_code=status.HTTP_201_CREATED,
)
async def create_packaged_scan(
    request: PackagedScanCreate,
    db: Session = Depends(get_db),
) -> PackagedScanRead:
    profile = db.get(UserProfile, LOCAL_PROFILE_ID)
    if profile is None:
        profile = UserProfile(id=LOCAL_PROFILE_ID)
        db.add(profile)
        db.flush()

    scan = FoodScan(id=uuid4(), profile_id=profile.id, status="completed")
    details = PackagedScanDetails(
        scan_id=scan.id,
        product_name=request.product_name,
        brand=request.brand,
        serving_size_g=request.serving_size_g,
        nutrition_basis=request.nutrition_basis,
        energy_kcal=request.energy_kcal,
        protein_g=request.protein_g,
        carbohydrates_g=request.carbohydrates_g,
        total_fat_g=request.total_fat_g,
        sodium_mg=request.sodium_mg,
        ingredients=request.ingredients,
        declared_allergens=request.declared_allergens,
        precautionary_allergen_statement=request.precautionary_allergen_statement,
    )
    db.add(scan)
    db.add(details)
    findings, goal_insight = analyze_confirmed_label(details, profile)
    details.goal_insight = goal_insight
    scan.findings.extend(findings)
    try:
        details.llm_explanation = await explain_packaged_label(
            details,
            findings,
            goal_insight,
            profile.goal,
            profile.daily_calorie_goal,
        )
    except GroqServiceError as error:
        db.rollback()
        raise HTTPException(
            status_code=error.status_code,
            detail=f"Groq explanation failed: {error}",
        ) from error
    db.commit()
    persisted_scan = _load_scan(db, scan.id)
    if persisted_scan is None:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail="The saved scan could not be reloaded",
        )
    return _scan_response(persisted_scan)


@router.get("/scans/{scan_id}", response_model=PackagedScanRead)
def get_scan(scan_id: UUID, db: Session = Depends(get_db)) -> PackagedScanRead:
    scan = _load_scan(db, scan_id)
    if scan is None or scan.profile_id != LOCAL_PROFILE_ID:
        raise HTTPException(status_code=404, detail="Scan not found")
    return _scan_response(scan)


def _load_scan(db: Session, scan_id: UUID) -> FoodScan | None:
    return (
        db.query(FoodScan)
        .options(
            selectinload(FoodScan.packaged_details),
            selectinload(FoodScan.findings),
            selectinload(FoodScan.profile),
        )
        .filter(FoodScan.id == scan_id)
        .one_or_none()
    )
