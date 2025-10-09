from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Interaction, Track, User
from ..core.security import decode_token
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

router = APIRouter(prefix="/interactions", tags=["interactions"])
auth_scheme = HTTPBearer()

class InteractionCreate(BaseModel):
    track_id: int | None = None
    seconds_listened: int
    is_completed: bool = False
    device: str | None = None
    context_type: str | None = None
    milestone: int | None = None  # 25,50,75,100 (percentage milestones)
    external_track_id: str | None = None

class InteractionOut(BaseModel):
    id: int
    track_id: int | None = None
    external_track_id: str | None = None
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
        external_track_id=payload.external_track_id,
        seconds_listened=payload.seconds_listened,
        is_completed=payload.is_completed,
        device=payload.device,
        context_type=payload.context_type,
        milestone=payload.milestone,
    )
    db.add(interaction)
    db.commit()
    db.refresh(interaction)
    return interaction


class ExternalInteractionCreate(BaseModel):
    external_track_id: str
    seconds_listened: int
    is_completed: bool = False
    device: str | None = None
    context_type: str | None = None
    milestone: int | None = None


@router.post('/external', response_model=InteractionOut)
def create_external_interaction(payload: ExternalInteractionCreate, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    # Create interaction referencing external provider id (e.g., Deezer preview id)
    interaction = Interaction(
        user_id=user_id,
        external_track_id=payload.external_track_id,
        seconds_listened=payload.seconds_listened,
        is_completed=payload.is_completed,
        device=payload.device,
        context_type=payload.context_type,
        milestone=payload.milestone,
    )
    db.add(interaction)
    db.commit()
    db.refresh(interaction)
    return interaction

@router.get('/recent', response_model=list[InteractionOut])
def recent(user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db), limit: int = 20):
    q = db.query(Interaction).filter(Interaction.user_id == user_id).order_by(Interaction.played_at.desc()).limit(limit).all()
    return q
