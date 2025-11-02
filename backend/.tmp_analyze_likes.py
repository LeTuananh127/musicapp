"""Compare recommendations with focus on liked tracks."""
import sys
sys.path.insert(0, 'c:\\musicapp\\backend')

from app.core.db import SessionLocal
from app.services.ml_recommendation_service import ml_recommendation_service
from app.models.music import Track, TrackLike

db = SessionLocal()

# Get User 4's liked tracks
likes = db.query(TrackLike.track_id).filter(TrackLike.user_id == 4).all()
liked_ids = {tid[0] for tid in likes}

print("="*80)
print("User 4's Liked Tracks Analysis")
print("="*80)

# Get recommendations
recommendations = ml_recommendation_service.recommend_for_user(
    db=db,
    user_id=4,
    limit=50,
    exclude_listened=False
)

# Get track details
track_ids = [tid for tid, _ in recommendations]
tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
track_dict = {t.id: t for t in tracks}

print(f"\nUser 4 has {len(liked_ids)} liked tracks:")
for tid in sorted(liked_ids):
    if tid in track_dict:
        t = track_dict[tid]
        print(f"  ❤️  [{tid:6d}] {t.title[:40]:40s} - {t.artist_name}")

print("\n" + "="*80)
print("Recommendations (showing liked tracks with ❤️):")
print("="*80 + "\n")

for i, (track_id, score) in enumerate(recommendations[:20], 1):
    if track_id in track_dict:
        t = track_dict[track_id]
        marker = "❤️ " if track_id in liked_ids else "   "
        print(f"{marker}{i:2d}. [{track_id:6d}] {t.title[:35]:35s} - {t.artist_name[:25]:25s} (score: {score:.2f})")

db.close()
