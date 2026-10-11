from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session

from app.db.session import get_db
from app.models import UserProfile
from app.schemas.profile import ProfileRead, ProfileUpdate

router = APIRouter()
LOCAL_PROFILE_ID = "local-development-profile"


@router.get("/me", response_model=ProfileRead)
def get_profile(db: Session = Depends(get_db)) -> UserProfile:
    profile = db.get(UserProfile, LOCAL_PROFILE_ID)
    if profile is None:
        profile = UserProfile(id=LOCAL_PROFILE_ID)
        db.add(profile)
        db.commit()
        db.refresh(profile)
    return profile


@router.put("/me/profile", response_model=ProfileRead)
def update_profile(
    update: ProfileUpdate, db: Session = Depends(get_db)
) -> UserProfile:
    profile = db.get(UserProfile, LOCAL_PROFILE_ID)
    if profile is None:
        profile = UserProfile(id=LOCAL_PROFILE_ID)
        db.add(profile)

    for field, value in update.model_dump(exclude_unset=True).items():
        setattr(profile, field, value)

    db.commit()
    db.refresh(profile)
    return profile
