from app.core.db import SessionLocal
from app.models.music import Interaction
from collections import defaultdict

db = SessionLocal()

# Replicate training logic
q = db.query(Interaction.user_id, Interaction.track_id, Interaction.is_completed, Interaction.milestone)
rows = q.filter(Interaction.track_id != None).all()

user_counts = defaultdict(int)
for u, t, completed, milestone in rows:
    if completed or (milestone is not None and milestone >= 75):
        user_counts[u] += 1

print("Users with qualified interactions (milestone>=75 or completed):")
for user_id in sorted(user_counts.keys()):
    print(f"  User {user_id}: {user_counts[user_id]} qualified interactions")

print(f"\nTotal users: {len(user_counts)}")

db.close()
