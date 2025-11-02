import os
import numpy as np
from typing import List, Dict, Tuple

MODEL_DIR = os.path.join(os.path.dirname(__file__), '..', '..', 'storage', 'recommender')
os.makedirs(MODEL_DIR, exist_ok=True)


class ALSRecommender:
    """Light wrapper around a saved ALS-style factorization.

    The training script writes a .npz with arrays:
      - user_ids: array of original user ids (int)
      - track_ids: array of original track ids (int)
      - user_factors: float matrix (n_users x k)
      - item_factors: float matrix (n_items x k)

    This class loads that artifact and exposes recommend(user_id, n).
    If no artifact is present, callers should fall back to the simple
    RecommendationService.
    """

    def __init__(self, path: str | None = None):
        self.path = path or os.path.join(MODEL_DIR, 'model.npz')
        self.user_ids = None
        self.track_ids = None
        self.user_factors = None
        self.item_factors = None
        self.user_index: Dict[int, int] = {}
        self.loaded = False
        self.load()

    def load(self):
        if not os.path.exists(self.path):
            self.loaded = False
            return
        data = np.load(self.path, allow_pickle=True)
        self.user_ids = data['user_ids']
        self.track_ids = data['track_ids']
        self.user_factors = data['user_factors']
        self.item_factors = data['item_factors']
        # build index for quick lookup
        self.user_index = {int(uid): idx for idx, uid in enumerate(self.user_ids)}
        self.loaded = True

    def recommend_for_user(self, user_id: int, topn: int = 20) -> List[Tuple[int, float]]:
        """Return list of (track_id, score) tuples ordered desc.

        If user_id not present in trained mapping, return empty list.
        """
        if not self.loaded:
            return []
        if int(user_id) not in self.user_index:
            return []
        uidx = self.user_index[int(user_id)]
        uvec = self.user_factors[uidx]
        # score = item_factors dot uvec
        scores = self.item_factors.dot(uvec)
        top_idx = np.argsort(scores)[::-1][:topn]
        out = [(int(self.track_ids[i]), float(scores[i])) for i in top_idx]
        return out


# module-level singleton convenience instance (will try to load on import)
recommender = ALSRecommender()
