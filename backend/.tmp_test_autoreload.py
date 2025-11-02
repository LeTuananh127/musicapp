"""Test auto-reload functionality of ML service."""
import sys
import time
import os
sys.path.insert(0, 'c:\\musicapp\\backend')

from app.core.db import SessionLocal
from app.services.ml_recommendation_service import ml_recommendation_service

db = SessionLocal()

print("="*80)
print("Testing Auto-Reload Functionality")
print("="*80)

# Test 1: Get current model info
print("\n1. Current model state:")
print(f"   Model loaded: {ml_recommendation_service.model_loaded}")
if ml_recommendation_service.model_loaded:
    print(f"   Users: {len(ml_recommendation_service.user_ids)}")
    print(f"   Tracks: {len(ml_recommendation_service.track_ids)}")
    print(f"   Last modified: {ml_recommendation_service._last_modified}")

# Test 2: Get recommendations (should NOT reload since file hasn't changed)
print("\n2. Getting recommendations (should NOT reload):")
recs = ml_recommendation_service.recommend_for_user(db, user_id=4, limit=5, exclude_listened=False)
print(f"   Received {len(recs)} recommendations")
if recs:
    print(f"   Top track: {recs[0]}")

# Test 3: Touch the model file to simulate update
print("\n3. Simulating model update (touching file)...")
model_path = "backend/storage/recommender/model.npz"
if os.path.exists(model_path):
    # Update modification time
    os.utime(model_path, None)
    print(f"   ✓ File timestamp updated")
    time.sleep(0.1)  # Small delay to ensure timestamp change
    
    # Test 4: Get recommendations again (should auto-reload)
    print("\n4. Getting recommendations again (should auto-reload):")
    recs = ml_recommendation_service.recommend_for_user(db, user_id=4, limit=5, exclude_listened=False)
    print(f"   Received {len(recs)} recommendations")
else:
    print(f"   ⚠️  Model file not found at {model_path}")

print("\n" + "="*80)
print("Auto-reload test completed!")
print("="*80)

db.close()
