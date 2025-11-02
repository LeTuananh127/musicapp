# AI Recommendation System - Setup Guide

## Overview
Hệ thống recommendation sử dụng **Matrix Factorization** (ALS - Alternating Least Squares) để đưa ra gợi ý cá nhân hóa dựa trên lịch sử nghe nhạc của người dùng.

## Architecture

### 1. Data Flow
```
User Interactions (plays, completes) 
    → interactions table (milestone >= 75 or is_completed)
    → train_recommender.py (ALS training)
    → model.npz (user/item embeddings)
    → ml_recommendation_service.py (serving)
    → API endpoints (/recommend/user/{id}/ml)
    → Flutter UI
```

### 2. Components

#### Backend Services
- **`ml_recommendation_service.py`**: Main ML service
  - Load model from NPZ file
  - Personalized recommendations (user × item dot product)
  - Similar tracks (cosine similarity)
  - Cold-start handling (popularity-based)
  - Fallback mechanisms

- **`train_recommender.py`**: Training script
  - Gather interactions (milestone >= 75 or completed)
  - Build sparse matrix (user × track)
  - Train ALS model (implicit library or SVD fallback)
  - Save to `backend/storage/recommender/model.npz`

- **`recommendation_service.py`**: Legacy fallback service
  - Pseudo-random recommendations
  - Used when ML model unavailable

#### Scripts
- **`scripts/train_model.py`**: Manual training runner
- **`scripts/scheduler.py`**: Scheduled training (daily at 3 AM)

#### API Endpoints
- `GET /recommend/user/{user_id}/ml?limit=20`
  - Personalized ML recommendations with metadata
  - Returns: `[{track_id, score, title, artist_name, ...}]`

- `GET /recommend/similar/{track_id}?limit=10`
  - Similar tracks based on embeddings
  - Returns: `[{track_id, score, title, artist_name, ...}]`

- `GET /recommend/user/{user_id}` (legacy)
  - Fallback pseudo-random recommendations

## Setup

### 1. Install Dependencies
```bash
cd backend
pip install -r requirements.txt
```

### 2. Train Initial Model
```bash
cd backend
python scripts/train_model.py
```

This creates `backend/storage/recommender/model.npz` with:
- `user_factors`: User embeddings (N_users × K dimensions)
- `item_factors`: Track embeddings (N_tracks × K dimensions)
- `user_ids`: User ID mapping
- `track_ids`: Track ID mapping

### 3. Start Backend
```bash
cd backend
uvicorn app.main:app --reload
```

The ML service auto-loads model on startup.

### 4. (Optional) Setup Scheduled Training
```bash
cd backend
python scripts/scheduler.py
```

Trains model daily at 3 AM and reloads service.

## Configuration

### Training Parameters
Edit `app/scripts/train_recommender.py`:
```python
factors = 64          # Embedding dimensions (default: 64)
iterations = 15       # ALS iterations (default: 15)
regularization = 0.01 # L2 regularization (default: 0.01)
```

### Interaction Filtering
Current criteria for positive signals:
- `milestone >= 75` (listened to 75%+)
- OR `is_completed = True`
- Confidence: `1.0 + 3.0` for qualified plays

### Cold Start Threshold
In `ml_recommendation_service.py`:
```python
COLD_START_THRESHOLD = 5  # Min interactions to use ML
```

## API Usage Examples

### Get Personalized Recommendations
```bash
curl http://localhost:8000/recommend/user/123/ml?limit=20
```

Response:
```json
[
  {
    "track_id": 456,
    "score": 0.87,
    "title": "Song Title",
    "artist_name": "Artist Name",
    "artist_id": 789,
    "album_id": 101,
    "duration_ms": 180000,
    "preview_url": "https://...",
    "cover_url": "https://..."
  },
  ...
]
```

### Get Similar Tracks
```bash
curl http://localhost:8000/recommend/similar/456?limit=10
```

Response: Same format as above

## Model Evaluation

### Metrics (TODO)
Add to `train_recommender.py`:
- Precision@K
- Recall@K
- NDCG (Normalized Discounted Cumulative Gain)
- AUC-ROC

### A/B Testing (TODO)
Compare ML vs baseline:
1. Split users into groups
2. Serve different recommendations
3. Measure engagement (completion rate, play time)

## Troubleshooting

### Model Not Loading
**Symptom**: Endpoint returns empty list or cold-start recommendations for all users

**Solutions**:
1. Check if `backend/storage/recommender/model.npz` exists
2. Run training: `python -m app.scripts.train_recommender`
3. Check logs for loading errors
4. Verify NPZ file has correct keys: `user_ids`, `track_ids`, `user_factors`, `item_factors`

### Low-Quality Recommendations
**Solutions**:
1. Check interaction data quality (milestone distribution)
2. Increase `factors` parameter (64 → 128)
3. Increase `iterations` (15 → 30)
4. Adjust interaction filtering criteria
5. Add more training data

### Cold Start for Existing Users
**Symptom**: Users with listening history get popularity-based recommendations

**Solutions**:
1. Check if user has >= 5 interactions in database
2. Verify user_id exists in `model.npz` mapping
3. Retrain model to include recent users

### Similar Tracks Not Working
**Solutions**:
1. Verify track_id exists in model
2. Check if track has enough interaction data
3. Retrain model with more data

## Performance Optimization

### Model Size
Current: ~64 dimensions × (N_users + N_tracks) × 4 bytes

For 10K users, 50K tracks:
- Memory: ~15 MB
- Load time: <1s

### Recommendation Speed
- Single user: ~10ms (dot product)
- Similar tracks: ~50ms (cosine similarity across all tracks)

### Optimization Ideas
1. Cache top-N recommendations per user
2. Use FAISS for approximate nearest neighbors
3. Precompute similar tracks matrix
4. Batch recommendations for multiple users

## Next Steps

1. ✅ Create API endpoints with metadata
2. ✅ Add scheduled training
3. ✅ Cold-start handling
4. ⏳ Update Flutter UI to consume `/ml` endpoints
5. ⏳ Add evaluation metrics to training
6. ⏳ Implement A/B testing framework
7. ⏳ Add caching layer (Redis)
8. ⏳ Model versioning strategy

## References
- [Implicit Library](https://github.com/benfred/implicit)
- [Matrix Factorization Guide](https://developers.google.com/machine-learning/recommendation/collaborative/matrix)
- [ALS Algorithm](https://spark.apache.org/docs/latest/ml-collaborative-filtering.html)
