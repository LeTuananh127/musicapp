from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..services.recommendation_service import recommendation_service
from ..services.ml_recommendation_service import ml_recommendation_service
from ..schemas.music import RecommendationOut, MLRecommendationOut
from ..models.music import Track

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

@router.get("/user/{user_id}/ml", response_model=list[MLRecommendationOut])
async def ml_recommend_for_user(
    user_id: int,
    limit: int = 20,
    exclude_listened: bool = False,  # Default False: recommend songs user likes
    db: Session = Depends(get_db),
):
    """
    Get ML-based personalized recommendations using Matrix Factorization.
    Returns tracks with scores and full metadata based on user's listening patterns.
    
    Args:
        user_id: User ID to get recommendations for
        limit: Number of recommendations to return
        exclude_listened: If True, only recommend new tracks. If False (default), 
                         recommend tracks similar to what user already likes.
    
    Falls back to popularity-based recommendations for new users.
    """
    # Get recommendations with scores
    recommendations = ml_recommendation_service.recommend_for_user(
        db=db,
        user_id=user_id,
        limit=limit,
        exclude_listened=exclude_listened
    )
    
    # Fetch track metadata
    track_ids = [tid for tid, _ in recommendations]
    tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
    
    # Create lookup dict
    track_dict = {track.id: track for track in tracks}
    
    # Build response with metadata
    result = []
    for track_id, score in recommendations:
        if track_id in track_dict:
            track = track_dict[track_id]
            result.append({
                "track_id": track_id,
                "score": score,
                "title": track.title,
                "artist_name": track.artist_name,
                "artist_id": track.artist_id,
                "album_id": track.album_id,
                "duration_ms": track.duration_ms,
                "preview_url": track.preview_url,
                "cover_url": track.cover_url,
            })
    
    return result


@router.get("/user/{user_id}/behavior", response_model=list[MLRecommendationOut])
async def behavioral_recommend_for_user(
    user_id: int,
    limit: int = 20,
    db: Session = Depends(get_db),
):
    """Per-user behavioral recommendations using only that user's listens and likes."""
    recs = ml_recommendation_service.recommend_behavioral(db=db, user_id=user_id, limit=limit)
    # Fetch metadata for tracks
    track_ids = [tid for tid, _ in recs]
    tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
    track_dict = {track.id: track for track in tracks}
    result = []
    for tid, score in recs:
        if tid in track_dict:
            t = track_dict[tid]
            result.append({
                "track_id": tid,
                "score": score,
                "title": t.title,
                "artist_name": t.artist_name,
                "artist_id": t.artist_id,
                "album_id": t.album_id,
                "duration_ms": t.duration_ms,
                "preview_url": t.preview_url,
                "cover_url": t.cover_url,
            })
    return result

@router.get("/similar/{track_id}", response_model=list[MLRecommendationOut])
async def get_similar_tracks(
    track_id: int,
    limit: int = 10,
    db: Session = Depends(get_db),
):
    """
    Get tracks similar to the given track using cosine similarity of item embeddings.
    Returns empty list if track not found or model not loaded.
    """
    # Get similar tracks
    similar = ml_recommendation_service.recommend_similar_tracks(
        db=db,
        track_id=track_id,
        limit=limit
    )
    
    # Fetch track metadata
    track_ids = [tid for tid, _ in similar]
    tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
    
    # Create lookup dict
    track_dict = {track.id: track for track in tracks}
    
    # Build response
    result = []
    for tid, score in similar:
        if tid in track_dict:
            track = track_dict[tid]
            result.append({
                "track_id": tid,
                "score": score,
                "title": track.title,
                "artist_name": track.artist_name,
                "artist_id": track.artist_id,
                "album_id": track.album_id,
                "duration_ms": track.duration_ms,
                "preview_url": track.preview_url,
                "cover_url": track.cover_url,
            })
    
    return result
