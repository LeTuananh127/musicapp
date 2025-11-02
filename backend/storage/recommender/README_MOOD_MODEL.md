# Mood Classification Model

## Overview
This directory contains the trained mood classification model based on the [Deezer Mood Detection Dataset](https://github.com/deezer/deezer_mood_detection_dataset).

## Files
- `deezer_mood_model.pkl` - RandomForest classifier (100 trees, max_depth=10)
- `encoder.pkl` - LabelEncoder for mood class names

## Model Details

### Input Features
- **Valence**: Musical positivity (happiness vs sadness)
- **Arousal**: Musical energy/intensity (calm vs energetic)

### Feature Scaling
**IMPORTANT:** The model was trained on Deezer dataset where valence/arousal are **already scaled** (range ~ -2.3 to +2.8).

Database tracks typically have **raw values** in range [0, 1]. The backend code **automatically converts** raw to scaled:
```python
scaled_valence = (raw_valence - 0.5) * 4.0
scaled_arousal = (raw_arousal - 0.5) * 4.0
```

### Mood Classes
The model classifies into 4 moods based on valence-arousal quadrants:

| Valence | Arousal | Mood | Description |
|---------|---------|------|-------------|
| High (≥0.0) | High (≥0.0) | **energetic** | Happy & energetic songs (pop, dance, EDM) |
| High (≥0.0) | Low (<0.0) | **relaxed** | Happy & calm songs (chill, acoustic) |
| Low (<0.0) | High (≥0.0) | **angry** | Dark & intense songs (rock, metal) |
| Low (<0.0) | Low (<0.0) | **sad** | Dark & calm songs (ballads, melancholic) |

*Note: Thresholds use scaled values (0.0), which is the natural center of the Deezer dataset (mean≈0)*

### Class Distribution (Training Data)
- **energetic**: 32.2% (6,001 samples) - Well balanced!
- **sad**: 29.2% (5,444 samples)
- **angry**: 19.5% (3,638 samples)
- **relaxed**: 19.1% (3,561 samples)

*Using threshold=0.0 provides much better class balance (ratio 0.59) compared to threshold=1.0 (ratio 0.08)*

### Performance
- **Cross-validation Accuracy**: 99.99%
- **Dataset Size**: 18,644 tracks (train + test + validation)

## Training
Model was trained using `backend/scripts/train_deezer_mood_model.py`:
```bash
cd backend/scripts
python train_deezer_mood_model.py
```

## Usage Example
```python
import joblib
import numpy as np

# Load model and encoder
model = joblib.load('storage/recommender/deezer_mood_model.pkl')
encoder = joblib.load('storage/recommender/encoder.pkl')

# Example: database track with raw values
raw_valence = 0.8  # High positivity
raw_arousal = 0.2  # Low energy

# Convert to scaled range
scaled_valence = (raw_valence - 0.5) * 4.0  # = 1.2
scaled_arousal = (raw_arousal - 0.5) * 4.0  # = -1.2

# Predict mood
pred_class = model.predict([[scaled_valence, scaled_arousal]])[0]
mood = encoder.classes_[pred_class]
print(f"Mood: {mood}")  # Output: "relaxed"
```

## Dependencies
- scikit-learn >= 1.5.1
- joblib >= 1.3.0
- numpy >= 1.24.0

## Notes
- No StandardScaler needed (raw→scaled conversion is simple linear mapping)
- Encoder maps class indices (0,1,2,3) to mood names alphabetically: ['angry', 'energetic', 'relaxed', 'sad']
- Model expects scaled features; backend automatically handles conversion
