from app.core.db import SessionLocal
from app.models.music import Interaction

db = SessionLocal()

# Check interactions for users 4 and 30
for user_id in [4, 30]:
    interactions = db.query(Interaction).filter(Interaction.user_id == user_id).all()
    qualified = [i for i in interactions if (i.milestone and i.milestone >= 75) or i.is_completed]
    
    print(f"\nUser {user_id}:")
    print(f"  Total interactions: {len(interactions)}")
    print(f"  Qualified (milestone>=75 or completed): {len(qualified)}")
    
    if qualified:
        print(f"  Sample qualified tracks: {[i.track_id for i in qualified[:5]]}")

db.close()
