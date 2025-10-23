from pydantic import BaseModel
from datetime import datetime
from typing import Optional

class TrackOut(BaseModel):
    id: int
    title: str
    artist_name: str | None = None
    artist_id: int
    album_id: Optional[int]
    duration_ms: int
    preview_url: Optional[str]
    cover_url: Optional[str]
    views: int = 0
    class Config:
        from_attributes = True

class RecommendationOut(BaseModel):
    track_id: int
    score: float

class PlaylistOut(BaseModel):
    id: int
    name: str
    description: Optional[str]

class MoodOut(BaseModel):
    id: int
    label: str
    confidence: Optional[float]
    created_at: datetime
