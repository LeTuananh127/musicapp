from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Playlist, PlaylistTrack, Track
from ..core.security import decode_token
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

router = APIRouter(prefix="/playlists", tags=["playlists"])
auth_scheme = HTTPBearer()

class PlaylistCreate(BaseModel):
    name: str
    description: str | None = None
    is_public: bool = True

class PlaylistOut(BaseModel):
    id: int
    name: str
    description: str | None
    is_public: bool
    class Config:
        from_attributes = True

class AddTrack(BaseModel):
    track_id: int

class PlaylistWithMeta(PlaylistOut):
    track_count: int

class PlaylistTrackOut(BaseModel):
    track_id: int
    position: int
    title: str | None = None
    artist_id: int | None = None
    duration_ms: int | None = None
    class Config:
        from_attributes = True

class ReorderPayload(BaseModel):
    ordered_track_ids: list[int]


def get_current_user_id(cred: HTTPAuthorizationCredentials = Depends(auth_scheme)) -> int:
    sub = decode_token(cred.credentials)
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid token")
    return int(sub)


def get_optional_user_id(request: Request) -> int | None:
    """Try to extract bearer token from Authorization header and decode it. Return user id int or None."""
    auth = request.headers.get('authorization')
    if not auth:
        return None
    parts = auth.split()
    if len(parts) != 2 or parts[0].lower() != 'bearer':
        return None
    token = parts[1]
    sub = decode_token(token)
    try:
        return int(sub) if sub else None
    except Exception:
        return None

@router.post('/', response_model=PlaylistOut)
def create_playlist(payload: PlaylistCreate, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    playlist = Playlist(user_id=user_id, name=payload.name, description=payload.description, is_public=payload.is_public)
    db.add(playlist)
    db.commit()
    db.refresh(playlist)
    return playlist

@router.get('/', response_model=list[PlaylistOut])
def list_playlists(user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    return db.query(Playlist).filter(Playlist.user_id == user_id).all()

@router.get('/{playlist_id}', response_model=PlaylistWithMeta)
def get_playlist(playlist_id: int, user_id: int = Depends(get_optional_user_id), db: Session = Depends(get_db)):
    # allow unauthenticated read access to public playlists; owner can always read
    playlist = db.query(Playlist).filter(Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    # if playlist is private, require owner
    if not playlist.is_public and playlist.user_id != user_id:
        raise HTTPException(status_code=404, detail="Playlist not found")
    track_count = db.query(PlaylistTrack).filter(PlaylistTrack.playlist_id == playlist_id).count()
    return PlaylistWithMeta(id=playlist.id, name=playlist.name, description=playlist.description, is_public=playlist.is_public, track_count=track_count)

@router.get('/{playlist_id}/tracks', response_model=list[PlaylistTrackOut])
def playlist_tracks(playlist_id: int, user_id: int = Depends(get_optional_user_id), db: Session = Depends(get_db)):
    # allow unauthenticated read access to tracks of public playlists; owner can read private playlists
    playlist = db.query(Playlist).filter(Playlist.id == playlist_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    if not playlist.is_public and playlist.user_id != user_id:
        raise HTTPException(status_code=404, detail="Playlist not found")
    rows = (
        db.query(PlaylistTrack, Track)
        .join(Track, Track.id == PlaylistTrack.track_id)
        .filter(PlaylistTrack.playlist_id == playlist_id)
        .order_by(PlaylistTrack.position.asc())
        .all()
    )
    out: list[PlaylistTrackOut] = []
    for pt, t in rows:
        out.append(PlaylistTrackOut(
            track_id=pt.track_id,
            position=pt.position,
            title=getattr(t, 'title', None),
            artist_id=getattr(t, 'artist_id', None),
            duration_ms=getattr(t, 'duration_ms', None)
        ))
    return out

@router.post('/{playlist_id}/tracks')
def add_track(playlist_id: int, body: AddTrack, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    playlist = db.query(Playlist).filter(Playlist.id == playlist_id, Playlist.user_id == user_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    track = db.query(Track).filter(Track.id == body.track_id).first()
    if not track:
        raise HTTPException(status_code=404, detail="Track not found")
    # find max position
    max_pos = db.query(PlaylistTrack).filter(PlaylistTrack.playlist_id == playlist_id).count()
    pt = PlaylistTrack(playlist_id=playlist_id, track_id=body.track_id, position=max_pos)
    db.add(pt)
    db.commit()
    return {"added": True}

@router.delete('/{playlist_id}/tracks/{track_id}')
def remove_track(playlist_id: int, track_id: int, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    row = db.query(PlaylistTrack).filter(PlaylistTrack.playlist_id == playlist_id, PlaylistTrack.track_id == track_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Track not in playlist")
    db.delete(row)
    db.commit()
    return {"removed": True}

@router.patch('/{playlist_id}/reorder')
def reorder_tracks(playlist_id: int, payload: ReorderPayload, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    playlist = db.query(Playlist).filter(Playlist.id == playlist_id, Playlist.user_id == user_id).first()
    if not playlist:
        raise HTTPException(status_code=404, detail="Playlist not found")
    rows = db.query(PlaylistTrack).filter(PlaylistTrack.playlist_id == playlist_id).all()
    id_to_row = {r.track_id: r for r in rows}
    if set(payload.ordered_track_ids) != set(id_to_row.keys()):
        raise HTTPException(status_code=400, detail="Track id set mismatch")
    for idx, tid in enumerate(payload.ordered_track_ids):
        id_to_row[tid].position = idx
    db.commit()
    return {"reordered": True, "count": len(payload.ordered_track_ids)}

@router.get('/track-memberships/{track_id}', response_model=list[int])
def track_memberships(track_id: int, user_id: int = Depends(get_current_user_id), db: Session = Depends(get_db)):
    """Return playlist IDs (owned by current user) that already contain the given track."""
    rows = (
        db.query(PlaylistTrack.playlist_id)
        .join(Playlist, Playlist.id == PlaylistTrack.playlist_id)
        .filter(PlaylistTrack.track_id == track_id, Playlist.user_id == user_id)
        .all()
    )
    return [r[0] for r in rows]
