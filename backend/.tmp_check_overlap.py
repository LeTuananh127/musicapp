from app.core.db import SessionLocal
from app.models.music import Interaction
import numpy as np

db = SessionLocal()

# Load model to check
model_path = "backend/storage/recommender/model.npz"
data = np.load(model_path)
track_ids = data['track_ids']

print(f"Total tracks in model: {len(track_ids)}")
print(f"Track IDs in model: {sorted(track_ids)[:10]}...")

# Check User 4's listened tracks
user_4_interactions = db.query(Interaction.track_id).filter(
    Interaction.user_id == 4,
    Interaction.track_id != None
).distinct().all()

listened_track_ids = {tid for (tid,) in user_4_interactions}
print(f"\nUser 4 has listened to {len(listened_track_ids)} unique tracks (with track_id)")

# Check overlap with model tracks
model_track_set = set(track_ids)
overlap = listened_track_ids & model_track_set
not_listened = model_track_set - listened_track_ids

print(f"Tracks in model that User 4 has listened to: {len(overlap)}")
print(f"Tracks in model that User 4 has NOT listened to: {len(not_listened)}")

if not_listened:
    print(f"\nUnlistened tracks available for recommendation: {sorted(not_listened)[:10]}...")

db.close()
