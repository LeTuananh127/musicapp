# Quick Start - AI Recommendation System

## 🚀 Getting Started in 5 Minutes

### 1. Install Dependencies
```powershell
cd c:\musicapp\backend
pip install -r requirements.txt
```

### 2. Train Initial Model
```powershell
cd c:\musicapp\backend
python scripts\train_model.py
```

Expected output:
```
INFO - Gathering interactions...
INFO - Found 5000 interactions from 150 users on 800 tracks
INFO - Building sparse matrix...
INFO - Training model with ALS...
INFO - Model saved to backend/storage/recommender/model.npz
```

### 3. Start Backend Server
```powershell
cd c:\musicapp\backend
uvicorn app.main:app --reload
```

### 4. Test Endpoints
Open new terminal:
```powershell
cd c:\musicapp\backend
python tests/test_ml_endpoints.py
```

### 5. Try in Browser
- Personalized recommendations: http://localhost:8000/recommend/user/1/ml?limit=20
- Similar tracks: http://localhost:8000/recommend/similar/1?limit=10
- API docs: http://localhost:8000/docs

## 📊 What's Happening?

### Model Training
1. **Gather Data**: Fetches interactions where user listened >= 75% or completed track
2. **Build Matrix**: Creates sparse user × track matrix (confidence = 1.0 + 3.0 for qualified plays)
3. **Train ALS**: Learns 64-dimensional embeddings for users and tracks
4. **Save Model**: Stores in `backend/storage/recommender/model.npz`

### Serving Recommendations
1. **Load Model**: Service loads embeddings on startup
2. **User Request**: `GET /recommend/user/123/ml`
3. **Score Tracks**: Compute `user_vector · track_vectors` for all tracks
4. **Filter**: Remove already-listened tracks
5. **Rank**: Sort by score, return top-N with metadata

### Cold Start Handling
- **New users** (<5 interactions): Get popularity-based recommendations
- **New tracks**: Won't appear in recommendations until model retrained
- **Fallback**: If model not loaded, uses legacy pseudo-random

## 🔄 Scheduled Training

### Option 1: Manual Retrain
```powershell
cd c:\musicapp\backend
python scripts/train_model.py
```

### Option 2: Scheduled (Daily at 3 AM)
```powershell
cd c:\musicapp\backend
python scripts/scheduler.py
```

Keep this running in background or use Windows Task Scheduler.

## 📱 Frontend Integration (Next Step)

Update `recommend_screen.dart`:
```dart
// Change endpoint from /recommend/user/{id} to /recommend/user/{id}/ml
final response = await http.get(
  Uri.parse('$baseUrl/recommend/user/$userId/ml?limit=20')
);

// Response includes full track metadata
final recommendations = (jsonDecode(response.body) as List)
  .map((item) => Track.fromJson(item))
  .toList();
```

## ⚡ Performance Tips

1. **Cache recommendations**: Store in Redis for 1 hour
2. **Batch requests**: Fetch recommendations for multiple users at once
3. **Async training**: Train model in background, don't block API
4. **Monitor metrics**: Track recommendation click-through rate

## 🐛 Common Issues

### "Model not found"
➡️ Run: `python -m app.scripts.train_recommender`

### "No recommendations returned"
➡️ Check if user has >= 5 interactions in database

### "Empty similar tracks list"
➡️ Verify track_id exists and has interaction data

### Import errors
➡️ Make sure you're in `backend/` directory when running scripts

## 📈 Next Steps

1. ✅ Test endpoints with real data
2. ⏳ Update Flutter UI to use `/ml` endpoint
3. ⏳ Add recommendation tracking (clicks, plays)
4. ⏳ Implement A/B testing (ML vs baseline)
5. ⏳ Add evaluation metrics (precision@K, recall@K)
6. ⏳ Set up automated retraining pipeline

## 📚 Full Documentation
See `backend/docs/ML_RECOMMENDATION_SETUP.md` for detailed architecture and configuration options.
