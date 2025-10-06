from sqlalchemy.orm import Session
import math, random
from typing import Optional

class RecommendationService:
    """Fallback recommendation logic.
    Later this will load ALS factors. Current behavior:
      - Deterministic pseudo-random ranking per user.
      - Score = base (inverse log) + small jitter.
      - Optional start_id / max_track_id filtering parameters.
    """

    def recommend_for_user(
        self,
        db: Session,
        user_id: int,
        limit: int = 20,
        start_id: int = 1,
        max_track_id: Optional[int] = None,
    ) -> list[tuple[int, float]]:
        rng = random.Random(user_id)
        if max_track_id is None:
            # probe max track id quickly (could be large; optimize later)
            from ..models.music import Track
            last = db.query(Track.id).order_by(Track.id.desc()).first()
            max_track_id = last[0] if last else 200
        candidates = list(range(start_id, max_track_id + 1))
        rng.shuffle(candidates)
        picked = candidates[: limit * 2]  # over-sample slightly
        scored: list[tuple[int, float]] = []
        for idx, tid in enumerate(picked):
            base = 1 / (1 + math.log(idx + 2))
            jitter = rng.random() * 0.05
            scored.append((tid, base + jitter))
        scored.sort(key=lambda x: x[1], reverse=True)
        return scored[:limit]

recommendation_service = RecommendationService()
