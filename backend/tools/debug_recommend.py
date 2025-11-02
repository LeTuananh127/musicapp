from sqlalchemy import func, distinct, or_, cast, String
from app.core.db import SessionLocal
from app.models.music import Playlist, PlaylistTrack, Track, Interaction

# Set artist IDs to test. Replace or add IDs as needed.
artist_ids = [13425, 13445, 17603]

session = SessionLocal()
try:
    print(f"Testing recommend_playlists for artists: {artist_ids}")
    plays_weight = 1
    match_weight = 10
    seconds_per_equivalent_play = 30.0

    # Apply explicit collation to avoid mixed-collation errors (matches onboard.py)
    ext_cast = cast(Track.id, String).collate('utf8mb4_unicode_ci')
    ext_col = Interaction.external_track_id.collate('utf8mb4_unicode_ci')

    stmt = (
        session.query(
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
    if out_sorted:
        print('Playlists matched:')
        for o in out_sorted:
            print(f"  id={o['id']} name={o['name']} score={o['score']:.2f} matches={o['matches']} plays_seconds={o['plays_seconds']}")
    else:
        print('No playlists matched; running fallback (top playlists by track count)')
        fallback_rows = (
            session.query(Playlist.id, Playlist.name, func.count(PlaylistTrack.track_id).label('track_count'))
            .join(PlaylistTrack, Playlist.id == PlaylistTrack.playlist_id)
            .group_by(Playlist.id, Playlist.name)
            .order_by(func.count(PlaylistTrack.track_id).desc())
            .limit(10)
            .all()
        )
        print('Fallback playlists:')
        for r in fallback_rows:
            print(f"  id={r.id} name={r.name} track_count={r.track_count}")
finally:
    session.close()
