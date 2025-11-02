"""Test ML recommendations directly without API server."""
import sys
sys.path.insert(0, 'c:\\musicapp\\backend')

from app.core.db import SessionLocal
from app.services.ml_recommendation_service import ml_recommendation_service

db = SessionLocal()

print("="*60)
print("Testing ML Recommendations for User 4 (Direct Call)")
print("="*60)

# Test with exclude_listened=True (default)
print("\n1. With exclude_listened=True (chỉ bài chưa nghe):")
recommendations = ml_recommendation_service.recommend_for_user(
    db=db,
    user_id=4,
    limit=20,
    exclude_listened=True
)
print(f"   Received {len(recommendations)} recommendations")
for i, (track_id, score) in enumerate(recommendations[:5], 1):
    print(f"   {i}. Track {track_id}: score={score:.4f}")

# Test with exclude_listened=False (include đã nghe)
print("\n2. With exclude_listened=False (bao gồm cả bài đã nghe):")
recommendations = ml_recommendation_service.recommend_for_user(
    db=db,
    user_id=4,
    limit=20,
    exclude_listened=False
)
print(f"   Received {len(recommendations)} recommendations")

# Get track details
from app.models.music import Track
track_ids = [tid for tid, _ in recommendations[:10]]
tracks = db.query(Track).filter(Track.id.in_(track_ids)).all()
track_dict = {t.id: t for t in tracks}

print("\n   Top 10 recommendations with metadata:")
for i, (track_id, score) in enumerate(recommendations[:10], 1):
    if track_id in track_dict:
        t = track_dict[track_id]
        print(f"   {i}. [{track_id:6d}] {t.title[:35]:35s} - {t.artist_name} (score: {score:.4f})")
    else:
        print(f"   {i}. Track {track_id}: score={score:.4f} (not found in DB)")

db.close()
print("\n" + "="*60)
