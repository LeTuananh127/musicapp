from app.core.db import SessionLocal
from app.models.music import Interaction

db = SessionLocal()

# Check interactions for users 4 and 30
for user_id in [4, 30]:
    all_int = db.query(Interaction).filter(Interaction.user_id == user_id).all()
    with_track_id = [i for i in all_int if i.track_id is not None]
    qualified = [i for i in all_int if (i.milestone and i.milestone >= 75) or i.is_completed]
    qualified_with_track = [i for i in qualified if i.track_id is not None]
    
    print(f"\nUser {user_id}:")
    print(f"  Total interactions: {len(all_int)}")
    print(f"  With track_id: {len(with_track_id)}")
    print(f"  Qualified (milestone>=75 or completed): {len(qualified)}")
    print(f"  Qualified WITH track_id: {len(qualified_with_track)}")
    
    if qualified_with_track:
        print(f"  Sample qualified track_ids: {[i.track_id for i in qualified_with_track[:5]]}")
    else:
        print(f"  ⚠️  All qualified interactions use external_track_id only!")

db.close()
