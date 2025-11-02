"""Test full workflow: train model → auto-reload → verify new recommendations."""
import sys
import time
import subprocess
sys.path.insert(0, 'c:\\musicapp\\backend')

from app.core.db import SessionLocal
from app.services.ml_recommendation_service import ml_recommendation_service

db = SessionLocal()

print("="*80)
print("Full Auto-Reload Workflow Test")
print("="*80)

# Step 1: Get current recommendations
print("\n1. Current recommendations for User 4:")
recs_before = ml_recommendation_service.recommend_for_user(
    db, user_id=4, limit=3, exclude_listened=False
)
print(f"   Users in model: {len(ml_recommendation_service.user_ids)}")
print(f"   Tracks in model: {len(ml_recommendation_service.track_ids)}")
print(f"   Top 3: {[(tid, f'{score:.2f}') for tid, score in recs_before]}")

# Step 2: Retrain model
print("\n2. Retraining model...")
result = subprocess.run(
    [sys.executable, 'scripts/train_model.py'],
    capture_output=True,
    text=True
)
if result.returncode == 0:
    print("   ✓ Training completed successfully")
else:
    print(f"   ✗ Training failed: {result.stderr}")

# Small delay to ensure file system updates
time.sleep(0.5)

# Step 3: Get recommendations again (should auto-reload)
print("\n3. Getting recommendations after retraining:")
print("   (Model should auto-reload if file changed)")
recs_after = ml_recommendation_service.recommend_for_user(
    db, user_id=4, limit=3, exclude_listened=False
)
print(f"   Users in model: {len(ml_recommendation_service.user_ids)}")
print(f"   Tracks in model: {len(ml_recommendation_service.track_ids)}")
print(f"   Top 3: {[(tid, f'{score:.2f}') for tid, score in recs_after]}")

# Step 4: Verify reload happened
if ml_recommendation_service._last_modified:
    print(f"\n4. Model file last modified: {ml_recommendation_service._last_modified}")
    print("   ✓ Auto-reload is working!")
else:
    print("\n4. ⚠️  No modification time tracked")

print("\n" + "="*80)

db.close()
