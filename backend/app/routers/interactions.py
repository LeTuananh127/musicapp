from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Interaction, Track, User
from ..core.security import decode_token
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from ..services.ml_recommendation_service import ml_recommendation_service

router = APIRouter(prefix="/interactions", tags=["interactions"])
auth_scheme = HTTPBearer()

class InteractionCreate(BaseModel):
    track_id: int | None = None
    seconds_listened: int
    is_completed: bool = False
    device: str | None = None
    context_type: str | None = None
    milestone: int | None = None  # 25,50,75,100 (percentage milestones)
    # external_track_id removed: the app uses internal `track_id` only

class InteractionOut(BaseModel):
    id: int
    track_id: int | None = None
    seconds_listened: int
    is_completed: bool
    milestone: int | None = None
    class Config:
        from_attributes = True


def get_current_user_id(cred: HTTPAuthorizationCredentials = Depends(auth_scheme)) -> int:
    sub = decode_token(cred.credentials)
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid token")
    return int(sub)

@router.post('/', response_model=InteractionOut)
def create_interaction(payload: InteractionCreate, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    # If an internal track_id is provided, validate it. Otherwise allow external_track_id.
    if payload.track_id is not None:
        track = db.query(Track).filter(Track.id == payload.track_id).first()
        if not track:
            raise HTTPException(status_code=404, detail="Track not found")
    interaction = Interaction(
        user_id=user_id,
        track_id=payload.track_id,
        seconds_listened=payload.seconds_listened,
        is_completed=payload.is_completed,
        device=payload.device,
        context_type=payload.context_type,
        milestone=payload.milestone,
    )
    db.add(interaction)
    db.commit()
    db.refresh(interaction)
    # Trigger best-effort async retrain/update of ML model when new interaction is created
    try:
        ml_recommendation_service.maybe_retrain_async(db)
    except Exception:
        # don't fail the request if retrain scheduling fails
        pass
    return interaction


class ExternalInteractionCreate(BaseModel):
    # external interactions endpoint removed - app records using internal track_id
    pass


@router.post('/external', response_model=InteractionOut)
def create_external_interaction(*_args, **_kwargs):
    # Endpoint intentionally removed. Return 404-like behavior through raising.
    raise HTTPException(status_code=404, detail="External interactions are no longer supported; use /interactions/ with track_id")

@router.get('/recent', response_model=list[InteractionOut])
def recent(user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db), limit: int = 20):
    q = db.query(Interaction).filter(Interaction.user_id == user_id).order_by(Interaction.played_at.desc()).limit(limit).all()
    return q
