from fastapi import APIRouter, Depends, HTTPException, Request
from sqlalchemy.orm import Session
from typing import List
from ..core.db import get_db
from ..models.music import UserPreferredArtist, Playlist, PlaylistTrack, Track, Interaction
from sqlalchemy import func, distinct, or_, cast, String
from ..routers.auth import _get_current_user as _get_current_user


def get_current_user(request: Request, db: Session = Depends(get_db)):
    # wrapper to call the internal auth helper to avoid FastAPI introspection problems
    return _get_current_user(request, db)
from pydantic import BaseModel
from datetime import datetime

router = APIRouter()

class PreferredArtistsIn(BaseModel):
    artist_ids: List[int]

class PlaylistOut(BaseModel):
    id: int
    name: str
    score: int

@router.post('/users/me/preferences/artists')
async def set_preferred_artists(payload: PreferredArtistsIn, db: Session = Depends(get_db), user=Depends(get_current_user)):
    user_id = user.id
    # remove existing
    db.query(UserPreferredArtist).filter(UserPreferredArtist.user_id == user_id).delete()
    # Bulk insert
    for aid in payload.artist_ids:
        up = UserPreferredArtist(user_id=user_id, artist_id=aid, created_at=datetime.utcnow())
        db.add(up)
    db.commit()
    return {"status": "ok", "count": len(payload.artist_ids)}


@router.get('/users/me/preferences/artists', response_model=List[int])
async def get_preferred_artists(db: Session = Depends(get_db), user=Depends(get_current_user)):
    user_id = user.id
    rows = db.query(UserPreferredArtist.artist_id).filter(UserPreferredArtist.user_id == user_id).all()
    return [r[0] for r in rows]

@router.get('/recommend/playlists', response_model=List[PlaylistOut])
async def recommend_playlists(artists: str, db: Session = Depends(get_db)):
    # artists param: comma-separated artist ids
    try:
        artist_ids = [int(x) for x in artists.split(',') if x]
    except Exception:
        raise HTTPException(status_code=400, detail='Invalid artists param')
    if not artist_ids:
        return []
    # advanced scoring:
    # match_count = number of distinct tracks in playlist from selected artists
    # plays_count = number of interactions for those tracks (plays)
    # final score = plays_weight * plays_count + match_weight * match_count
    plays_weight = 1
    match_weight = 10

    # count interactions that reference either the internal track_id or the external_track_id
    # aggregate total seconds listened for matched tracks, then convert to equivalent plays
    seconds_per_equivalent_play = 30.0
    # ensure the string comparison uses the same collation to avoid MySQL collation mix errors
    ext_cast = cast(Track.id, String).collate('utf8mb4_unicode_ci')
    ext_col = Interaction.external_track_id.collate('utf8mb4_unicode_ci')

    stmt = (
        db.query(
            Playlist.id.label('pid'),
            Playlist.name.label('pname'),
            func.count(distinct(PlaylistTrack.track_id)).label('match_count'),
            func.coalesce(func.sum(Interaction.seconds_listened), 0).label('plays_seconds'),
        )
        .join(PlaylistTrack, Playlist.id == PlaylistTrack.playlist_id)
        .join(Track, Track.id == PlaylistTrack.track_id)
    .outerjoin(Interaction, or_(Interaction.track_id == Track.id, ext_col == ext_cast))
        .filter(Track.artist_id.in_(artist_ids))
        .group_by(Playlist.id, Playlist.name)
    )

    rows = stmt.all()
    out = []
    for r in rows:
        pid = r.pid
        pname = r.pname
        match_count = int(r.match_count or 0)
        plays_seconds = float(r.plays_seconds or 0)
        equivalent_plays = plays_seconds / seconds_per_equivalent_play if plays_seconds > 0 else 0.0
        score = plays_weight * equivalent_plays + match_weight * match_count
        out.append({'id': pid, 'name': pname, 'score': score, 'matches': match_count, 'plays_seconds': plays_seconds, 'equivalent_plays': equivalent_plays})

    out_sorted = sorted(out, key=lambda x: x['score'], reverse=True)
    # return only id, name, score (ensure score is int to match response model)
    if out_sorted:
        return [{'id': o['id'], 'name': o['name'], 'score': int(round(o['score']))} for o in out_sorted]

    # Fallback: if no playlists matched, return top playlists by number of tracks (popularity proxy)
    fallback_rows = (
        db.query(Playlist.id, Playlist.name, func.count(PlaylistTrack.track_id).label('track_count'))
        .join(PlaylistTrack, Playlist.id == PlaylistTrack.playlist_id)
        .group_by(Playlist.id, Playlist.name)
        .order_by(func.count(PlaylistTrack.track_id).desc())
        .limit(10)
        .all()
    )
    return [{'id': r.id, 'name': r.name, 'score': 0} for r in fallback_rows]
