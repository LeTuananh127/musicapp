from app.core.db import SessionLocal
from app.models.music import TrackLike, Track

db = SessionLocal()

# Check likes for user 4
likes = db.query(TrackLike).filter(TrackLike.user_id == 4).all()

print(f"User 4 has {len(likes)} liked tracks\n")

if likes:
    print("Liked tracks:")
    track_ids = [like.track_id for like in likes]
    tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
    track_dict = {t.id: t for t in tracks}
    
    for like in likes[:20]:  # Show first 20
        track = track_dict.get(like.track_id)
        if track:
            print(f"  [{like.track_id:6d}] {track.title[:40]:40s} - {track.artist_name}")
        else:
            print(f"  [{like.track_id:6d}] (Track not found)")
else:
    print("No liked tracks found")

db.close()
