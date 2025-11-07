from fastapi import APIRouter, Depends, HTTPException, Response, UploadFile, File, Form, Query
from fastapi.responses import FileResponse
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Track, TrackLike, Artist, User
import math
from io import BytesIO
import struct
import os
from typing import List
from sqlalchemy import or_
from ..models.music import Artist
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from ..core.security import decode_token
from ..schemas.music import TrackOut

router = APIRouter(prefix="/tracks", tags=["tracks"])
auth_scheme = HTTPBearer()


def _get_current_user(cred: HTTPAuthorizationCredentials = Depends(auth_scheme), db: Session = Depends(get_db)) -> User:
    sub = decode_token(cred.credentials)
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid token")
    user = db.query(User).filter(User.id == int(sub)).first()
    if not user:
        raise HTTPException(status_code=401, detail="User not found")
    return user

@router.get("/", response_model=list[TrackOut])
async def list_tracks(
    db: Session = Depends(get_db),
    limit: int = 50,
    offset: int = 0,
    order: str = 'desc',
):
    """List tracks with simple offset pagination.

    Params:
      - limit: max rows (capped at 200)
      - offset: skip rows
      - order: 'asc' | 'desc' by id (defaults to newest first)
    """
    limit = min(max(limit, 1), 200)
    base = db.query(Track)
    if order.lower() == 'asc':
        base = base.order_by(Track.id.asc())
    else:
        base = base.order_by(Track.id.desc())
    rows = base.offset(offset).limit(limit).all()
    # Ensure preview_url fallback if none stored and file exists
    dirty = False
    for t in rows:
        if not t.preview_url:
            for ext in ('wav','mp3'):
                file_path = f'app/static/audio/{t.id}.{ext}'
                if os.path.exists(file_path):
                    t.preview_url = f'/tracks/{t.id}/preview'
                    dirty = True
                    break
    if dirty:
        db.commit()
    return rows

@router.post('/upload', response_model=TrackOut)
async def upload_track(
    title: str = Form(...),
    artist_id: int | None = Form(None),
    duration_ms: int = Form(...),
    audio: UploadFile = File(...),
    cover: UploadFile | None = File(None),
    db: Session = Depends(get_db),
    current_user: User = Depends(_get_current_user),
):
    # Save audio file as {new_id}.wav (or keep extension)
    # Ensure artist exists; if artist_id not provided or doesn't exist, create artist for current_user
    artist = None
    if artist_id is not None:
        artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        # create a new artist using current user's display_name if available
        artist_name = current_user.display_name or current_user.email or f'Artist {current_user.id}'
        artist = Artist(name=artist_name, cover_url=None, created_by=current_user.id)
        db.add(artist)
        db.commit()
        db.refresh(artist)

    track = Track(title=title, artist_id=artist.id, album_id=None, duration_ms=duration_ms, preview_url=None, cover_url=None, is_explicit=False)
    db.add(track)
    db.commit()
    db.refresh(track)
    audio_dir = 'app/static/audio'
    os.makedirs(audio_dir, exist_ok=True)
    ext = os.path.splitext(audio.filename or '')[1] or '.wav'
    audio_path = os.path.join(audio_dir, f'{track.id}{ext}')
    with open(audio_path, 'wb') as f:
        f.write(await audio.read())
    # set preview_url
    track.preview_url = f'/tracks/{track.id}/preview'
    if cover:
        cover_dir = 'app/static/covers'
        os.makedirs(cover_dir, exist_ok=True)
        cover_ext = os.path.splitext(cover.filename or '')[1] or '.jpg'
        cover_path = os.path.join(cover_dir, f'{track.id}{cover_ext}')
        with open(cover_path, 'wb') as f:
            f.write(await cover.read())
        track.cover_url = f'/static/covers/{track.id}{cover_ext}'
    db.add(track)
    db.commit()
    db.refresh(track)
    return track

@router.post('/bulk', response_model=list[TrackOut])
async def bulk_create_tracks(
    titles: List[str] = Form(...),
    artist_ids: List[int] = Form(...),
    durations_ms: List[int] = Form(...),
    db: Session = Depends(get_db),
):
    if not (len(titles) == len(artist_ids) == len(durations_ms)):
        raise HTTPException(status_code=400, detail='Array lengths mismatch')
    created: list[Track] = []
    for title, artist_id, dur in zip(titles, artist_ids, durations_ms):
        tr = Track(title=title, artist_id=artist_id, album_id=None, duration_ms=dur, preview_url=None, cover_url=None, is_explicit=False)
        db.add(tr)
        created.append(tr)
    db.commit()
    for tr in created:
        db.refresh(tr)
    return created


@router.post('/create', response_model=TrackOut)
async def create_track_with_urls(
    payload: dict,
    db: Session = Depends(get_db),
    current_user: User = Depends(_get_current_user),
):
    """Create a track record using external audio/cover URLs (no file upload).

    Expects JSON body: {"title": str, "artist_id": int, "duration_ms": int, "audio_url": str (optional), "cover_url": str (optional)}
    """
    title = payload.get('title')
    artist_id = payload.get('artist_id')
    duration_ms = payload.get('duration_ms', 0)
    audio_url = payload.get('audio_url')
    cover_url = payload.get('cover_url')
    if not title:
        raise HTTPException(status_code=400, detail='Missing title')
    # Ensure artist exists; if artist_id not provided or invalid, create new artist for current user
    artist = None
    if artist_id:
        artist = db.query(Artist).filter(Artist.id == artist_id).first()
    if not artist:
        artist_name = current_user.display_name or current_user.email or f'Artist {current_user.id}'
        artist = Artist(name=artist_name, cover_url=None, created_by=current_user.id)
        db.add(artist)
        db.commit()
        db.refresh(artist)

    tr = Track(title=title, artist_id=artist.id, album_id=None, duration_ms=duration_ms, preview_url=None, cover_url=None, is_explicit=False)
    if audio_url:
        tr.preview_url = audio_url
    if cover_url:
        tr.cover_url = cover_url
    db.add(tr)
    db.commit()
    db.refresh(tr)
    return tr

@router.api_route('/{track_id}/preview', methods=['GET', 'HEAD'])
def track_preview(track_id: int, db: Session = Depends(get_db)):
    track = db.query(Track).filter(Track.id == track_id).first()
    if not track:
        raise HTTPException(status_code=404, detail='Track not found')
    # If a real audio file exists (wav or mp3) serve it instead of generated tone
    for ext, mime in [('wav','audio/wav'), ('mp3','audio/mpeg')]:
        static_path = f'app/static/audio/{track_id}.{ext}'
        if os.path.exists(static_path):
            return FileResponse(static_path, media_type=mime)
    # Simple generated sine wave tone 5 seconds, 44.1kHz, 16-bit mono
    sample_rate = 44100
    duration_s = 5
    freq = 440.0 + (track_id % 5) * 110  # vary a little
    num_samples = sample_rate * duration_s
    amplitude = 16000
    buf = BytesIO()
    # WAV header
    def write_fmt(fmt, *vals):
        buf.write(struct.pack(fmt, *vals))
    # RIFF header
    buf.write(b'RIFF')
    buf.write(b'0000')  # placeholder for size
    buf.write(b'WAVE')
    # fmt chunk
    buf.write(b'fmt ')
    write_fmt('<I', 16)  # PCM chunk size
    write_fmt('<H', 1)   # PCM format
    write_fmt('<H', 1)   # channels
    write_fmt('<I', sample_rate)
    write_fmt('<I', sample_rate * 2)  # byte rate (sample_rate * block_align)
    write_fmt('<H', 2)   # block align (channels * bytes/sample)
    write_fmt('<H', 16)  # bits per sample
    # data chunk
    buf.write(b'data')
    buf.write(b'0000')  # placeholder for data size
    for n in range(num_samples):
        sample = int(amplitude * math.sin(2 * math.pi * freq * (n / sample_rate)))
        write_fmt('<h', sample)
    data = buf.getvalue()
    # fill sizes
    data_size = num_samples * 2
    riff_size = 4 + (8 + 16) + (8 + data_size)
    data = data[:4] + struct.pack('<I', riff_size) + data[8:40] + struct.pack('<I', data_size) + data[44:]
    return Response(content=data, media_type='audio/wav')

def _current_user_id(cred: HTTPAuthorizationCredentials = Depends(auth_scheme)) -> int:
    sub = decode_token(cred.credentials)
    if not sub:
        raise HTTPException(status_code=401, detail="Invalid token")
    return int(sub)

@router.post('/{track_id}/like')
def like_track(track_id: int, db: Session = Depends(get_db), user_id: int = Depends(_current_user_id)):
    track = db.query(Track).filter(Track.id == track_id).first()
    if not track:
        raise HTTPException(status_code=404, detail="Track not found")
    existing = db.query(TrackLike).filter(TrackLike.user_id == user_id, TrackLike.track_id == track_id).first()
    if existing:
        return {"liked": True}
    like = TrackLike(user_id=user_id, track_id=track_id)
    db.add(like)
    db.commit()
    return {"liked": True}

@router.delete('/{track_id}/like')
def unlike_track(track_id: int, db: Session = Depends(get_db), user_id: int = Depends(_current_user_id)):
    row = db.query(TrackLike).filter(TrackLike.user_id == user_id, TrackLike.track_id == track_id).first()
    if not row:
        raise HTTPException(status_code=404, detail="Not liked")
    db.delete(row)
    db.commit()
    return {"liked": False}

@router.get('/liked')
def liked_tracks(db: Session = Depends(get_db), user_id: int = Depends(_current_user_id)):
    rows = db.query(TrackLike.track_id).filter(TrackLike.user_id == user_id).all()
    return [r[0] for r in rows]

@router.get('/search', response_model=list[TrackOut])
async def search_tracks(
    q: str = Query(..., min_length=1, description='Search query'),
    limit: int = Query(10, ge=1, le=200),
    offset: int = Query(0, ge=0),
    db: Session = Depends(get_db),
):
    """Search tracks by title or artist name (case-insensitive).

    Returns up to `limit` matching tracks.
    """
    # simple ILIKE search on title and artist name
    q_like = f"%{q}%"
    rows = db.query(Track).join(Artist, Track.artist).filter(or_(Track.title.ilike(q_like), Artist.name.ilike(q_like))).offset(offset).limit(limit).all()
    # Fallback implementation: if nothing matched via join, try title-only search
    if not rows:
        rows = db.query(Track).filter(Track.title.ilike(q_like)).offset(offset).limit(limit).all()
    return rows


@router.get('/{track_id}')
def get_track(track_id: int, db: Session = Depends(get_db)):
    track = db.query(Track).filter(Track.id == track_id).first()
    if not track:
        raise HTTPException(status_code=404, detail="Track not found")
    return track


@router.post('/{track_id}/view')
def increment_view(track_id: int, db: Session = Depends(get_db)):
    """Increment view counter for a track. Safe to call frequently."""
    tr = db.query(Track).filter(Track.id == track_id).first()
    if not tr:
        raise HTTPException(status_code=404, detail='Track not found')
    try:
        tr.views = (tr.views or 0) + 1
        db.add(tr)
        db.commit()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    return {"views": tr.views}
