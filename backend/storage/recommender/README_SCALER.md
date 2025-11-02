# Mood Model & Scaler Setup

## 📦 Required Files

Upload the following files to `backend/storage/recommender/`:

1. **deezer_mood_model.pkl** ✅ (Already present)
   - RandomForestClassifier trained with scikit-learn
   - Input: [valence, arousal] (scaled)
   - Output: class label (0, 1, 2, 3)

2. **scaler.pkl** ⚠️ (MISSING - Required for accurate predictions!)
   - StandardScaler used during training
   - Transforms raw [valence, arousal] → scaled features
   - **CRITICAL**: Model was trained on scaled data!

3. **encoder.pkl** (Optional, not currently used)
   - LabelEncoder for mood labels
   - Backend uses model.classes_ instead

## 🚨 IMPORTANT: Why Scaler is Needed

Your training code:
```python
scaler = StandardScaler()
X_scaled = scaler.fit_transform(X)  # ← Features were scaled!
model.fit(X_scaled, y)               # ← Model trained on scaled data
```

**Without scaler**, backend predictions will be **WRONG** because:
- Training: features scaled to mean=0, std=1
- Inference (current): raw features (mean≠0, std≠1)
- → Model sees completely different feature distribution!

## ✅ How to Fix

### Option 1: Upload scaler.pkl (Recommended)
1. Locate `scaler.pkl` from your training output
2. Upload to `C:\musicapp\backend\storage\recommender\scaler.pkl`
3. Restart backend → scaler will be auto-loaded

### Option 2: Retrain model WITHOUT scaler
If you don't have scaler.pkl:
```python
# In training code, REMOVE these lines:
# scaler = StandardScaler()
# X_scaled = scaler.fit_transform(X)

# Train directly on raw features:
model.fit(X, y_encoded)  # ← Use X instead of X_scaled
joblib.dump(model, "deezer_mood_model.pkl")
# Don't save scaler
```

## 🧪 Testing

After uploading scaler.pkl:

```bash
# 1. Restart backend
cd C:\musicapp\backend
python -m uvicorn app.main:app --reload --host 127.0.0.1 --port 8000

# 2. Check logs - should see:
# [mood] Loaded scaler from ...scaler.pkl

# 3. Test prediction
curl http://127.0.0.1:8000/mood/status
# Should show: scaler_loaded: true (if we add this field)

# 4. Test recommendation
curl -X POST http://127.0.0.1:8000/mood/recommend/from_db \
  -H "Content-Type: application/json" \
  -d '{"user_text":"chill","top_k":5}'
```

## 📊 Class Mapping

Model output (from LabelEncoder, alphabetical order):
- `0` → **angry**
- `1` → **energetic**
- `2` → **relaxed**
- `3` → **sad**

Backend automatically maps numeric predictions to string labels using `model.classes_`.

## 🔧 Backend Changes Made

1. Added `_scaler` global variable
2. Modified `_load_model()` to load scaler.pkl from same directory
3. Created `_predict_mood_with_model()` helper:
   - Applies scaler.transform() if scaler available
   - Maps numeric class → string label using model.classes_
   - Returns (predicted_label, confidence_score)
4. Updated both endpoints to use new helper function

## 📝 Next Steps

1. **Upload scaler.pkl** to this directory
2. Restart backend
3. Test predictions → should be much more accurate!
4. (Optional) Upload encoder.pkl for completeness
