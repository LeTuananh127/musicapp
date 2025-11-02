"""Test recommendations for users NOT in training data."""
import sys
sys.path.insert(0, 'c:\\musicapp\\backend')

from app.core.db import SessionLocal
from app.services.ml_recommendation_service import ml_recommendation_service
from app.models.music import User

db = SessionLocal()

print("="*80)
print("Testing Recommendations for Non-Trained Users")
print("="*80)

# Get users in model
trained_users = set(ml_recommendation_service.user_ids.tolist()) if ml_recommendation_service.model_loaded else set()
print(f"\nUsers in trained model: {sorted(trained_users)}")

# Get all users from DB
all_users = db.query(User.id).limit(20).all()
all_user_ids = [uid[0] for uid in all_users]
print(f"All users in DB (first 20): {sorted(all_user_ids)}")

# Find users NOT in model
non_trained = [uid for uid in all_user_ids if uid not in trained_users]
print(f"\nUsers NOT in model: {sorted(non_trained)}")

# Test recommendations for non-trained users
print("\n" + "="*80)
print("Testing recommendations for non-trained users:")
print("="*80)

test_users = non_trained[:5]  # Test first 5 non-trained users
for user_id in test_users:
    print(f"\n--- User {user_id} (NOT in model) ---")
    
    recs = ml_recommendation_service.recommend_for_user(
        db=db,
        user_id=user_id,
        limit=5,
        exclude_listened=False
    )
    
    if recs:
        print(f"✓ Received {len(recs)} recommendations")
        print(f"  Top 3: {[(tid, f'{score:.2f}') for tid, score in recs[:3]]}")
        print(f"  Strategy: Cold-start (popularity-based)")
    else:
        print(f"✗ No recommendations")

# Compare with trained user
print("\n" + "="*80)
print("Compare with trained user (User 4):")
print("="*80)

recs_trained = ml_recommendation_service.recommend_for_user(
    db=db,
    user_id=4,
    limit=5,
    exclude_listened=False
)
print(f"✓ User 4 (trained): {len(recs_trained)} recommendations")
print(f"  Top 3: {[(tid, f'{score:.2f}') for tid, score in recs_trained[:3]]}")
print(f"  Strategy: ML-based (personalized)")

db.close()
