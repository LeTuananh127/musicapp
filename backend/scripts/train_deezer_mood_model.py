"""
Train mood classification model using official Deezer dataset
Dataset features already scaled (valence/arousal range ~ -2.3 to +2.8)
"""
import pandas as pd
import numpy as np
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.model_selection import cross_val_score
import joblib
import os

def classify_mood(valence, arousal):
    """
    Classify mood based on valence-arousal quadrants
    Uses threshold=0.0 (the natural center of Deezer scaled data)
    
    Data analysis shows:
    - Valence mean=-0.067, median=0.032 → center at 0
    - Arousal mean=0.196, median=0.040 → center at 0
    - Threshold=0.0 gives balanced classes (19-32% each)
    - Threshold=1.0 gives imbalanced classes (73% sad!)
    """
    if valence >= 0.0 and arousal >= 0.0:
        return "energetic"
    elif valence >= 0.0 and arousal < 0.0:
        return "relaxed"
    elif valence < 0.0 and arousal >= 0.0:
        return "angry"
    else:
        return "sad"

# Load datasets
print("Loading Deezer datasets...")
train_df = pd.read_csv('train.csv')
test_df = pd.read_csv('test.csv')
val_df = pd.read_csv('validation.csv')

print(f"Train: {len(train_df)} samples")
print(f"Test: {len(test_df)} samples")
print(f"Validation: {len(val_df)} samples")

# Check value ranges
print(f"\nValence range: {train_df['valence'].min():.2f} to {train_df['valence'].max():.2f}")
print(f"Arousal range: {train_df['arousal'].min():.2f} to {train_df['arousal'].max():.2f}")

# Combine all datasets for training (standard practice)
combined_df = pd.concat([train_df, test_df, val_df], ignore_index=True)
print(f"\nCombined dataset: {len(combined_df)} samples")

# Classify moods
print("\nClassifying moods...")
combined_df['mood'] = combined_df.apply(
    lambda row: classify_mood(row['valence'], row['arousal']),
    axis=1
)

# Check class distribution
print("\nMood distribution:")
print(combined_df['mood'].value_counts())
print("\nMood percentages:")
print(combined_df['mood'].value_counts(normalize=True) * 100)

# Prepare features and labels
X = combined_df[['valence', 'arousal']].values
y = combined_df['mood'].values

# Encode labels
encoder = LabelEncoder()
y_encoded = encoder.fit_transform(y)
print(f"\nLabel encoding: {dict(zip(encoder.classes_, range(len(encoder.classes_))))}")

# Train RandomForest model
print("\nTraining RandomForest model...")
model = RandomForestClassifier(
    n_estimators=100,
    max_depth=10,
    random_state=42,
    n_jobs=-1
)

# Cross-validation
print("Running 5-fold cross-validation...")
cv_scores = cross_val_score(model, X, y_encoded, cv=5, scoring='accuracy')
print(f"CV Accuracy: {cv_scores.mean():.4f} (+/- {cv_scores.std():.4f})")

# Train final model on all data
print("\nTraining final model on all data...")
model.fit(X, y_encoded)

# Test predictions
print("\nTesting predictions on quadrant centers:")
test_cases = [
    (0.5, 0.5, "energetic"),   # Positive valence, positive arousal
    (0.5, -0.5, "relaxed"),    # Positive valence, negative arousal
    (-0.5, 0.5, "angry"),      # Negative valence, positive arousal
    (-0.5, -0.5, "sad"),       # Negative valence, negative arousal
    (0.0, 0.0, "?"),           # Boundary case (could be any)
]

for v, a, expected in test_cases:
    pred_class = model.predict([[v, a]])[0]
    pred_label = encoder.classes_[pred_class]
    probs = model.predict_proba([[v, a]])[0]
    confidence = probs.max()
    print(f"  v={v:4.1f}, a={a:4.1f} -> {pred_label:10s} (confidence: {confidence:.2%}) [expected: {expected}]")

# Save model and encoder
output_dir = '../storage/recommender'
os.makedirs(output_dir, exist_ok=True)

model_path = os.path.join(output_dir, 'deezer_mood_model.pkl')
encoder_path = os.path.join(output_dir, 'encoder.pkl')

joblib.dump(model, model_path)
joblib.dump(encoder, encoder_path)

print(f"\n✅ Model saved to: {model_path}")
print(f"✅ Encoder saved to: {encoder_path}")
print(f"✅ Model classes: {encoder.classes_.tolist()}")
print(f"\n⚠️  NOTE: This model expects SCALED features (valence/arousal ~ -2 to +2)")
print(f"⚠️  Database tracks with raw 0-1 values must be scaled first!")
