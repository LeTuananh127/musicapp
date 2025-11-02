"""
Retrain mood model với threshold đúng (0.5 thay vì 1.0)

USAGE:
  python retrain_mood_model_fixed.py /path/to/train.csv

OUTPUT:
  - deezer_mood_model_v2.pkl
  - scaler_v2.pkl  
  - encoder_v2.pkl
"""
import sys
import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split, KFold
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder, StandardScaler
from sklearn.metrics import accuracy_score, classification_report
import joblib

def classify_mood(v, a):
    """Classify mood with CORRECT threshold (0.5, not 1.0)"""
    if v >= 0.5 and a >= 0.5:
        return "energetic"
    elif v >= 0.5 and a < 0.5:
        return "relaxed"
    elif v < 0.5 and a >= 0.5:
        return "angry"
    else:
        return "sad"

def main():
    if len(sys.argv) < 2:
        print("Usage: python retrain_mood_model_fixed.py <path_to_train.csv>")
        sys.exit(1)
    
    csv_path = sys.argv[1]
    
    # Read data
    print(f"📖 Reading data from {csv_path}...")
    df = pd.read_csv(csv_path)
    print(f"✅ Loaded {len(df)} rows")
    
    # Add mood column with CORRECT threshold
    print("\n🎯 Classifying moods with threshold=0.5...")
    df["mood"] = df.apply(lambda x: classify_mood(x["valence"], x["arousal"]), axis=1)
    
    # Check distribution
    print("\n📊 Mood distribution:")
    print(df["mood"].value_counts())
    
    # Keep necessary columns
    df = df[["valence", "arousal", "mood"]].dropna()
    
    # Shuffle
    df = df.sample(frac=1, random_state=42).reset_index(drop=True)
    
    # Split features and labels
    X = df[["valence", "arousal"]]
    y = df["mood"]
    
    # Standardize features
    print("\n⚙️ Scaling features...")
    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)
    
    # Encode labels
    encoder = LabelEncoder()
    y_encoded = encoder.fit_transform(y)
    
    print(f"📋 Classes: {encoder.classes_}")
    
    # Add small noise for augmentation
    noise = np.random.normal(0, 0.05, X_scaled.shape)
    X_augmented = X_scaled + noise
    
    # K-Fold Cross-Validation
    print("\n🔄 Training with 5-Fold Cross-Validation...")
    kf = KFold(n_splits=5, shuffle=True, random_state=42)
    accuracy_scores = []
    
    for fold, (train_index, test_index) in enumerate(kf.split(X_augmented)):
        print(f"\n--- Fold {fold+1} ---")
        X_train, X_test = X_augmented[train_index], X_augmented[test_index]
        y_train, y_test = y_encoded[train_index], y_encoded[test_index]
        
        model = RandomForestClassifier(
            n_estimators=100,
            max_depth=10,
            min_samples_split=5,
            min_samples_leaf=3,
            random_state=42
        )
        model.fit(X_train, y_train)
        
        y_pred = model.predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)
        report = classification_report(y_test, y_pred, target_names=encoder.classes_)
        
        accuracy_scores.append(accuracy)
        print(f"🎯 Accuracy: {accuracy:.4f}")
        print(f"📈 Classification Report:\n{report}")
    
    print(f"\n✅ Average Accuracy: {np.mean(accuracy_scores):.4f}")
    
    # Save final model (from last fold)
    output_dir = "."
    joblib.dump(model, f"{output_dir}/deezer_mood_model_v2.pkl")
    joblib.dump(scaler, f"{output_dir}/scaler_v2.pkl")
    joblib.dump(encoder, f"{output_dir}/encoder_v2.pkl")
    
    print(f"\n💾 Saved:")
    print(f"  - {output_dir}/deezer_mood_model_v2.pkl")
    print(f"  - {output_dir}/scaler_v2.pkl")
    print(f"  - {output_dir}/encoder_v2.pkl")
    
    # Test predictions
    print("\n🧪 Testing predictions:")
    test_cases = [
        (0.8, 0.2, "relaxed"),
        (0.8, 0.8, "energetic"),
        (0.2, 0.2, "sad"),
        (0.2, 0.8, "angry"),
    ]
    for v, a, expected in test_cases:
        scaled = scaler.transform([[v, a]])
        pred_idx = model.predict(scaled)[0]
        pred_label = encoder.classes_[pred_idx]
        probs = model.predict_proba(scaled)[0]
        confidence = probs[pred_idx]
        match = "✅" if pred_label == expected else "❌"
        print(f"  {match} v={v}, a={a} -> {pred_label} (expected: {expected}, conf: {confidence:.2f})")

if __name__ == "__main__":
    main()
