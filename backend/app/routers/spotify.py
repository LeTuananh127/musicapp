from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel
from ..services import spotify_service

router = APIRouter(prefix="/spotify", tags=["spotify"])

class SpotifyTrack(BaseModel):
    id: str
    name: str | None = None
    artists: list[str] = []
    album: str | None = None
    duration_ms: int | None = None
    preview_url: str | None = None
    external_url: str | None = None

@router.get("/search", response_model=list[SpotifyTrack])
def search(q: str = Query(..., min_length=1, description="Search query for tracks"), limit: int = Query(10, ge=1, le=50)):
    try:
        return [SpotifyTrack(**t) for t in spotify_service.search_tracks(q, limit=limit)]
    except spotify_service.SpotifyAuthError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Spotify error: {e}")

@router.get("/tracks/{track_id}", response_model=SpotifyTrack)
def get_track(track_id: str):
    try:
        return SpotifyTrack(**spotify_service.get_track(track_id))
    except KeyError:
        raise HTTPException(status_code=404, detail="Track not found")
    except spotify_service.SpotifyAuthError as e:
        raise HTTPException(status_code=500, detail=str(e))
    except Exception as e:
        raise HTTPException(status_code=502, detail=f"Spotify error: {e}")
