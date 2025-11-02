from app.core.db import SessionLocal
from app.models.music import Interaction, Track
from collections import Counter

db = SessionLocal()

# Get User 4's most played tracks
interactions = db.query(Interaction).filter(
    Interaction.user_id == 4,
    Interaction.track_id != None
).all()

# Count plays per track
track_plays = Counter()
track_completion = {}

for i in interactions:
    track_plays[i.track_id] += 1
    if i.track_id not in track_completion:
        track_completion[i.track_id] = {
            'completed': 0,
            'total': 0,
            'max_milestone': 0
        }
    track_completion[i.track_id]['total'] += 1
    if i.is_completed:
        track_completion[i.track_id]['completed'] += 1
    if i.milestone:
        track_completion[i.track_id]['max_milestone'] = max(
            track_completion[i.track_id]['max_milestone'],
            i.milestone
        )

# Get top 10 most played tracks with metadata
print("User 4's TOP TRACKS (by play count):\n")
for track_id, count in track_plays.most_common(10):
    track = db.query(Track).filter(Track.id == track_id).first()
    comp = track_completion[track_id]
    completion_rate = (comp['completed'] / comp['total'] * 100) if comp['total'] > 0 else 0
    
    if track:
        print(f"{count:3d} plays | [{track_id:6d}] {track.title[:40]:40s} - {track.artist_name}")
        print(f"        Completed: {comp['completed']}/{comp['total']} ({completion_rate:.0f}%), Max milestone: {comp['max_milestone']}")
    else:
        print(f"{count:3d} plays | Track {track_id} (not found in DB)")

db.close()
