from fastapi import APIRouter, Depends, Query
from typing import List, Optional
from ..core.db import get_db
from sqlalchemy.orm import Session
from ..models.music import Artist
from ..models.music import Track
from fastapi import HTTPException

router = APIRouter()


@router.get('/artists', response_model=List[dict])
def list_artists(
    limit: int = Query(50, ge=1, le=200),
    offset: int = Query(0, ge=0),
    q: Optional[str] = Query(None),
    db: Session = Depends(get_db),
):
    """Return a simple list of artists (id, name). Supports optional search 'q' and pagination via offset."""
    query = db.query(Artist)
    if q:
        # simple case-insensitive substring match
        query = query.filter(Artist.name.ilike(f"%{q}%"))
    query = query.order_by(Artist.name).offset(offset).limit(limit)
    rows = query.all()
    out = [{'id': a.id, 'name': a.name, 'cover_url': getattr(a, 'cover_url', None)} for a in rows]
    return out


@router.get('/artists/by_ids')
def artists_by_ids(ids: str, db: Session = Depends(get_db)):
    """Return artist id/name pairs for a comma-separated list of ids."""
    try:
        id_list = [int(x) for x in ids.split(',') if x]
    except Exception:
        raise HTTPException(status_code=400, detail='Invalid ids param')
    rows = db.query(Artist).filter(Artist.id.in_(id_list)).all()
    return [{'id': a.id, 'name': a.name, 'cover_url': getattr(a, 'cover_url', None)} for a in rows]


@router.get('/artists/tracks')
def tracks_by_artists(artists: str | None = None, limit: int = 200, offset: int = 0, db: Session = Depends(get_db)):
    """Return tracks matching the provided comma-separated artist ids. If 'artists' is None return empty list."""
    if not artists:
        raise HTTPException(status_code=400, detail='artists param required')
    try:
        artist_ids = [int(x) for x in artists.split(',') if x]
    except Exception:
        raise HTTPException(status_code=400, detail='Invalid artists param')
    q = db.query(Track).filter(Track.artist_id.in_(artist_ids)).order_by(Track.title).offset(offset).limit(limit)
    rows = q.all()
    out = []
    for t in rows:
        out.append({
            'id': t.id,
            'title': t.title,
            'artist_id': t.artist_id,
            'artist_name': t.artist_name,
            'duration_ms': t.duration_ms,
            'preview_url': t.preview_url,
            'cover_url': t.cover_url,
            'views': t.views,
        })
    return out
