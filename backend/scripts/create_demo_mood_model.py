import os
import joblib

# Dummy model that mimics sklearn classifier interface
class DummyMoodModel:
    def __init__(self):
        # classes correspond to moods
        self.classes_ = ['energetic', 'relaxed', 'angry', 'sad']

    def predict(self, X):
        # X is list-like of [valence, arousal]
        preds = []
        for v, a in X:
            if v >= 0.5 and a >= 0.5:
                preds.append('energetic')
            elif v >= 0.5 and a < 0.5:
                preds.append('relaxed')
            elif v < 0.5 and a >= 0.5:
                preds.append('angry')
            else:
                preds.append('sad')
        return preds

    def predict_proba(self, X):
        # return soft scores favoring the predicted class
        out = []
        for v, a in X:
            probs = [0.0]*4
            if v >= 0.5 and a >= 0.5:
                probs[0] = 0.9
            elif v >= 0.5 and a < 0.5:
                probs[1] = 0.9
            elif v < 0.5 and a >= 0.5:
                probs[2] = 0.9
            else:
                probs[3] = 0.9
            out.append(probs)
        return out


def main():
    dest = os.path.join(os.path.dirname(__file__), '..', 'storage', 'mood')
    os.makedirs(dest, exist_ok=True)
    path = os.path.join(dest, 'mood_model.pkl')
    model = DummyMoodModel()
    joblib.dump(model, path)
    print(f"Wrote demo model to {path}")

if __name__ == '__main__':
    main()
