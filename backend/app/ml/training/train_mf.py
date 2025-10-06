"""ALS / Matrix Factorization training pipeline (placeholder).
Run: python -m app.ml.training.train_mf
"""
from __future__ import annotations
import numpy as np
import pandas as pd
from pathlib import Path
from datetime import datetime

ARTIFACT_DIR = Path("app/ml/artifacts")
ARTIFACT_DIR.mkdir(parents=True, exist_ok=True)

# Placeholder training using random factors

def train(factors: int = 64, users: int = 100, items: int = 500):
    user_factors = np.random.rand(users, factors).astype(np.float32)
    item_factors = np.random.rand(items, factors).astype(np.float32)
    timestamp = datetime.utcnow().strftime('%Y%m%d%H%M%S')
    np.save(ARTIFACT_DIR / f"user_factors_{timestamp}.npy", user_factors)
    np.save(ARTIFACT_DIR / f"item_factors_{timestamp}.npy", item_factors)
    (ARTIFACT_DIR / 'latest.txt').write_text(timestamp)
    print("Saved factors with timestamp", timestamp)

if __name__ == "__main__":
    train()
