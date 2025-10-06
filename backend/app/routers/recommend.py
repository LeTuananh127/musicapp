from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..services.recommendation_service import recommendation_service
from ..schemas.music import RecommendationOut

router = APIRouter(prefix="/recommend", tags=["recommend"])

@router.get("/user/{user_id}", response_model=list[RecommendationOut])
async def recommend_for_user(
    user_id: int,
    limit: int = 20,
    start_id: int = 1,
    max_track_id: int | None = None,
    db: Session = Depends(get_db),
):
    scores = recommendation_service.recommend_for_user(db, user_id, limit, start_id=start_id, max_track_id=max_track_id)
    return [{"track_id": tid, "score": score} for tid, score in scores]
