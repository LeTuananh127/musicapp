"""Enhanced AI-powered recommendation service using Matrix Factorization.

This service loads a trained ALS/MF model and serves personalized recommendations
based on user listening behavior from the interactions table.
"""
import os
import numpy as np
from typing import Optional, List, Tuple
from sqlalchemy.orm import Session
from sqlalchemy import func
from datetime import datetime, timedelta
import threading
import subprocess
import sys
import json
from pathlib import Path

from ..models.music import Track, Interaction, UserFeatures, TrackLike
from sqlalchemy import case


class MLRecommendationService:
    """ML-powered recommendation service using trained Matrix Factorization model."""

    def __init__(self, model_path: str = "backend/storage/recommender/model.npz"):
        self.model_path = model_path
        self.model_loaded = False
        self.user_ids = None
        self.track_ids = None
        self.user_factors = None
        self.item_factors = None
        self.user_id_to_idx = {}
        self.track_id_to_idx = {}
        self._last_modified = None  # Track file modification time
        # metadata about last training run (written by trainer)
        self._meta_path = str(Path(self.model_path).with_name('model.meta.json'))
        self._last_trained_user_count = None
        self._last_trained_interaction_count = None
        self._startup_check_done = False
        # Retrain debounce/control
        self._retrain_lock = threading.Lock()
        self._retrain_in_progress = False
        self._last_retrain_scheduled_at = None
        # Configurable thresholds (environment overrides)
        self._retrain_debounce_seconds = int(os.getenv('RETRAIN_DEBOUNCE_SECONDS', '30'))
        self._retrain_interaction_delta = int(os.getenv('RETRAIN_INTERACTION_DELTA', '20'))
        self._retrain_user_delta = int(os.getenv('RETRAIN_USER_DELTA', '1'))
        self._load_model()
        # try to load metadata if provided
        self._load_meta()

    def _check_and_reload_if_needed(self):
        """Check if model file has been updated and reload if necessary."""
        try:
            if not os.path.exists(self.model_path):
                return
            
            current_mtime = os.path.getmtime(self.model_path)
            
            # If first time or file has been modified, reload
            if self._last_modified is None or current_mtime > self._last_modified:
                if self._last_modified is not None:
                    print(f"🔄 Model file updated, reloading...")
                self._load_model()
                self._last_modified = current_mtime
        except Exception as e:
            print(f"⚠️  Error checking model file: {e}")

    def _load_model(self):
        """Load the trained model from disk."""
        try:
            if not os.path.exists(self.model_path):
                print(f"⚠️  Model file not found: {self.model_path}")
                return

            data = np.load(self.model_path)
            self.user_ids = data['user_ids']
            self.track_ids = data['track_ids']
            self.user_factors = data['user_factors']
            self.item_factors = data['item_factors']

            # Build lookup dictionaries
            self.user_id_to_idx = {int(uid): idx for idx, uid in enumerate(self.user_ids)}
            self.track_id_to_idx = {int(tid): idx for idx, tid in enumerate(self.track_ids)}

            self.model_loaded = True
            
            # Update last modified time
            if os.path.exists(self.model_path):
                self._last_modified = os.path.getmtime(self.model_path)
            
            print(f"✅ ML model loaded: {len(self.user_ids)} users, {len(self.track_ids)} tracks")
            print(f"   Factor dimensions: {self.user_factors.shape[1]}")
        except Exception as e:
            print(f"❌ Failed to load ML model: {e}")
            self.model_loaded = False

    def _load_meta(self):
        """Load model metadata written by the training script if available."""
        try:
            if os.path.exists(self._meta_path):
                with open(self._meta_path, 'r', encoding='utf-8') as mf:
                    data = json.load(mf)
                self._last_trained_user_count = int(data.get('user_count') or 0)
                self._last_trained_interaction_count = int(data.get('interaction_count') or 0)
                print(f"ℹ️  Loaded model meta: users={self._last_trained_user_count}, interactions={self._last_trained_interaction_count}")
            else:
                # If meta not present but model is loaded, infer user count from model to avoid unnecessary retrain at startup
                if self.model_loaded and self.user_ids is not None:
                    try:
                        self._last_trained_user_count = int(len(self.user_ids))
                        self._last_trained_interaction_count = 0
                        print(f"ℹ️  No model meta found; inferring last_trained_user_count={self._last_trained_user_count} from model file")
                    except Exception:
                        pass
        except Exception as e:
            print(f"⚠️  Could not read model meta: {e}")

    def reload_model(self):
        """Reload the model from disk (useful after retraining)."""
        self.model_loaded = False
        self._load_model()

    def recommend_for_user(
        self,
        db: Session,
        user_id: int,
        limit: int = 20,
        exclude_listened: bool = True,
        min_score: float = 0.0,
    ) -> List[Tuple[int, float]]:
        """
        Get personalized recommendations for a user.
        
        Args:
            db: Database session
            user_id: User ID to get recommendations for
            limit: Number of recommendations to return
            exclude_listened: If True, exclude tracks user has already listened to
            min_score: Minimum score threshold for recommendations
            
        Returns:
            List of (track_id, score) tuples sorted by score descending
        """
        # On first request after service start, check DB stats and decide if retraining is needed
        if not self._startup_check_done:
            try:
                self.ensure_model_trained(db)
            except Exception as e:
                print(f"⚠️  ensure_model_trained failed: {e}")
            self._startup_check_done = True

        # Auto-reload model if file has been updated
        self._check_and_reload_if_needed()
        
        if not self.model_loaded:
            print(f"⚠️  ML model not loaded, using fallback recommendations for user {user_id}")
            return self._fallback_recommendations(db, user_id, limit)

        # Check if user exists in training data
        if user_id not in self.user_id_to_idx:
            print(f"ℹ️  User {user_id} not in training data, using cold-start strategy")
            return self._cold_start_recommendations(db, user_id, limit)

        user_idx = self.user_id_to_idx[user_id]
        user_vector = self.user_factors[user_idx]

        # Compute scores for all items
        scores = np.dot(self.item_factors, user_vector)

        # Get track IDs and scores
        recommendations = [
            (int(self.track_ids[idx]), float(score))
            for idx, score in enumerate(scores)
            if score >= min_score
        ]

        # Filter out tracks user has already listened to (optional)
        if exclude_listened:
            listened_track_ids = self._get_listened_tracks(db, user_id)
            recommendations = [
                (tid, score) for tid, score in recommendations
                if tid not in listened_track_ids
            ]

        # Sort by score descending
        recommendations.sort(key=lambda x: x[1], reverse=True)

        # Verify tracks exist in database
        recommendations = self._filter_existing_tracks(db, recommendations)

        # If we don't have enough recommendations, supplement with popular/similar tracks
        if len(recommendations) < limit:
            print(f"ℹ️  Only {len(recommendations)} recommendations from model, supplementing...")
            additional_needed = limit - len(recommendations)
            
            # Get already recommended track IDs
            recommended_ids = {tid for tid, _ in recommendations}
            if exclude_listened:
                recommended_ids.update(listened_track_ids)
            
            # Strategy: Get similar tracks to user's favorites
            supplemental = self._get_supplemental_recommendations(
                db, user_id, exclude_ids=recommended_ids, limit=additional_needed
            )
            
            # Add with decaying scores
            base_score = recommendations[-1][1] if recommendations else 0.0
            for i, tid in enumerate(supplemental):
                score = base_score * (0.95 ** (i + 1))  # Decay scores
                recommendations.append((tid, score))
            
        return recommendations[:limit]

    def _get_db_stats(self, db: Session) -> tuple[int, int]:
        """Return (user_count, interaction_count) for current DB state."""
        try:
            user_count = db.query(func.count()).select_from(__import__('app').models.music.User).scalar()  # type: ignore
        except Exception:
            # fallback - try direct query
            from ..models.music import User as _User  # type: ignore
            user_count = db.query(func.count()).select_from(_User).scalar()

        try:
            interaction_count = db.query(func.count()).select_from(__import__('app').models.music.Interaction).scalar()  # type: ignore
        except Exception:
            from ..models.music import Interaction as _Interaction  # type: ignore
            interaction_count = db.query(func.count()).select_from(_Interaction).scalar()

        return int(user_count or 0), int(interaction_count or 0)

    def ensure_model_trained(self, db: Session):
        """Ensure model exists and is reasonably up-to-date. If not, trigger a retrain.

        This method compares DB counts with the last trained metadata and runs the training
        script (synchronously) if new users or interactions have been added since last train.
        """
        # If model file does not exist, train now
        needs_train = False
        if not os.path.exists(self.model_path):
            print("🔎 Model file not found, will train a new model")
            needs_train = True

        # Load current DB stats
        try:
            user_count, interaction_count = self._get_db_stats(db)
        except Exception as e:
            print(f"⚠️  Could not read DB stats for retrain check: {e}")
            user_count, interaction_count = (0, 0)

        # Compare with metadata if available
        if (self._last_trained_user_count is None) or (self._last_trained_interaction_count is None):
            # No metadata available -> retrain at startup to ensure model matches DB
            print("ℹ️  No model metadata found; scheduling retrain at startup")
            needs_train = True
        else:
            if user_count > self._last_trained_user_count or interaction_count > self._last_trained_interaction_count:
                print(f"🔁 Detected new data (users {self._last_trained_user_count} -> {user_count} | interactions {self._last_trained_interaction_count} -> {interaction_count}), will retrain")
                needs_train = True

        if needs_train:
            # Run training synchronously; training script will save model and meta, then we reload model
            try:
                print("⚙️  Running training pipeline (this may take a while)...")
                # Determine script path relative to project
                project_root = Path(__file__).resolve().parents[2]
                script_path = project_root / 'scripts' / 'train_model.py'
                if script_path.exists():
                    subprocess.run([sys.executable, str(script_path)], check=True)
                else:
                    # Fall back to directly invoking tools trainer if importable
                    try:
                        from tools import train_recommender as trainer
                        trainer.main()
                    except Exception as e:
                        print(f"⚠️  Could not run training script: {e}")
                # Reload model after training
                self.reload_model()
                # reload metadata
                self._load_meta()
                # optionally save embeddings to DB
                try:
                    self.save_user_embeddings_to_db(db)
                except Exception as e:
                    print(f"⚠️  save_user_embeddings_to_db failed: {e}")
            except subprocess.CalledProcessError as e:
                print(f"❌ Training subprocess failed: {e}")
            except Exception as e:
                print(f"❌ Training failed: {e}")

    def maybe_retrain_async(self, db: Session):
        """Trigger retraining in background thread if new data appears.

        This starts a detached thread that runs the `scripts/train_model.py` script. It's
        intentionally best-effort: failures are logged but do not raise.
        """
        # Debounce and avoid concurrent retrains. Only schedule if DB shows enough new data
        now = datetime.utcnow()
        with self._retrain_lock:
            if self._retrain_in_progress:
                print("ℹ️  Retrain already in progress; skipping schedule")
                return
            if self._last_retrain_scheduled_at and (now - self._last_retrain_scheduled_at).total_seconds() < self._retrain_debounce_seconds:
                print(f"ℹ️  Retrain called too recently (<{self._retrain_debounce_seconds}s); skipping")
                return

            # Check db stats to see if retrain is warranted (avoid retraining for every single interaction)
            try:
                user_count, interaction_count = self._get_db_stats(db)
            except Exception as e:
                print(f"⚠️  Could not read DB stats before scheduling retrain: {e}")
                return

            users_delta = 0 if self._last_trained_user_count is None else max(0, user_count - self._last_trained_user_count)
            interactions_delta = 0 if self._last_trained_interaction_count is None else max(0, interaction_count - self._last_trained_interaction_count)

            if users_delta < self._retrain_user_delta and interactions_delta < self._retrain_interaction_delta:
                print(f"ℹ️  Retrain not needed yet (users Δ={users_delta}, interactions Δ={interactions_delta}); thresholds ({self._retrain_user_delta},{self._retrain_interaction_delta})")
                return

            # Mark scheduled
            self._last_retrain_scheduled_at = now
            self._retrain_in_progress = True

        def _worker():
            try:
                project_root = Path(__file__).resolve().parents[2]
                script_path = project_root / 'scripts' / 'train_model.py'
                if script_path.exists():
                    subprocess.run([sys.executable, str(script_path)], check=True)
                else:
                    from tools import train_recommender as trainer
                    trainer.main()
                # reload model and meta
                try:
                    self.reload_model()
                    self._load_meta()
                except Exception as e:
                    print(f"⚠️  Reload after async train failed: {e}")
            except Exception as e:
                print(f"⚠️  Async retrain failed: {e}")
            finally:
                with self._retrain_lock:
                    self._retrain_in_progress = False

        t = threading.Thread(target=_worker, daemon=True)
        t.start()

    def recommend_similar_tracks(
        self,
        db: Session,
        track_id: int,
        limit: int = 10,
    ) -> List[Tuple[int, float]]:
        """
        Find similar tracks based on item embeddings.
        
        Args:
            db: Database session
            track_id: Track ID to find similar tracks for
            limit: Number of similar tracks to return
            
        Returns:
            List of (track_id, similarity_score) tuples
        """
        # Auto-reload model if file has been updated
        self._check_and_reload_if_needed()
        
        if not self.model_loaded or track_id not in self.track_id_to_idx:
            return []

        track_idx = self.track_id_to_idx[track_id]
        track_vector = self.item_factors[track_idx]

        # Compute cosine similarity with all other tracks
        norms = np.linalg.norm(self.item_factors, axis=1)
        track_norm = np.linalg.norm(track_vector)
        
        if track_norm == 0:
            return []

        similarities = np.dot(self.item_factors, track_vector) / (norms * track_norm)

        # Get similar tracks (excluding the track itself)
        similar = [
            (int(self.track_ids[idx]), float(sim))
            for idx, sim in enumerate(similarities)
            if idx != track_idx
        ]

        similar.sort(key=lambda x: x[1], reverse=True)
        similar = self._filter_existing_tracks(db, similar)

        return similar[:limit]

    def get_user_embedding(self, user_id: int) -> Optional[np.ndarray]:
        """Get the latent embedding vector for a user."""
        if not self.model_loaded or user_id not in self.user_id_to_idx:
            return None
        user_idx = self.user_id_to_idx[user_id]
        return self.user_factors[user_idx].copy()

    def save_user_embeddings_to_db(self, db: Session):
        """Save user embeddings to database for future use."""
        if not self.model_loaded:
            return

        for user_id in self.user_ids:
            embedding = self.get_user_embedding(int(user_id))
            if embedding is not None:
                # Convert numpy array to list for JSON storage
                vector_data = {
                    'embedding': embedding.tolist(),
                    'model_version': 'als_v1',
                    'created_at': datetime.utcnow().isoformat(),
                }

                # Upsert user features using session.merge to avoid race/duplicate errors
                try:
                    uf = UserFeatures(
                        user_id=int(user_id),
                        latent_vector=vector_data,
                        updated_at=datetime.utcnow()
                    )
                    db.merge(uf)
                except Exception:
                    # fallback: try to update existing record if merge fails
                    existing = db.query(UserFeatures).filter_by(user_id=int(user_id)).first()
                    if existing:
                        existing.latent_vector = vector_data
                        existing.updated_at = datetime.utcnow()
                    else:
                        # give up silently; commit may raise and will be handled by caller
                        pass

        db.commit()
        print(f"✅ Saved embeddings for {len(self.user_ids)} users to database")

    def _get_listened_tracks(self, db: Session, user_id: int, days: int = 90) -> set:
        """Get set of track IDs user has listened to recently."""
        cutoff = datetime.utcnow() - timedelta(days=days)
        interactions = (
            db.query(Interaction.track_id)
            .filter(
                Interaction.user_id == user_id,
                Interaction.track_id.isnot(None),
                Interaction.played_at >= cutoff
            )
            .all()
        )
        return {int(i[0]) for i in interactions if i[0] is not None}

    def _filter_existing_tracks(
        self, db: Session, recommendations: List[Tuple[int, float]]
    ) -> List[Tuple[int, float]]:
        """Filter out tracks that don't exist in database."""
        if not recommendations:
            return []

        track_ids = [tid for tid, _ in recommendations]
        existing = db.query(Track.id).filter(Track.id.in_(track_ids)).all()
        existing_set = {int(tid[0]) for tid in existing}

        return [(tid, score) for tid, score in recommendations if tid in existing_set]

    def _cold_start_recommendations(
        self, db: Session, user_id: int, limit: int
    ) -> List[Tuple[int, float]]:
        """
        Recommendations for new users (cold start).
        Use popularity-based recommendations.
        """
        # Get most popular tracks from interactions
        from sqlalchemy import func, desc

        popular = (
            db.query(
                Interaction.track_id,
                func.count(Interaction.id).label('play_count')
            )
            .filter(Interaction.track_id.isnot(None))
            .group_by(Interaction.track_id)
            .order_by(desc('play_count'))
            .limit(limit * 2)
            .all()
        )

        # Normalize scores to 0-1 range
        if not popular:
            return []

        max_count = popular[0][1]
        recommendations = [
            (int(tid), float(count) / max_count)
            for tid, count in popular
            if tid is not None
        ]

        return recommendations[:limit]

    def _fallback_recommendations(
        self, db: Session, user_id: int, limit: int
    ) -> List[Tuple[int, float]]:
        """Fallback recommendations when model is not available."""
        import random
        import math

        rng = random.Random(user_id)
        
        # Get max track ID
        last = db.query(Track.id).order_by(Track.id.desc()).first()
        max_track_id = last[0] if last else 200
        
        # Generate pseudo-random recommendations
        candidates = list(range(1, max_track_id + 1))
        rng.shuffle(candidates)
        picked = candidates[:limit * 2]
        
        scored = [
            (tid, 1 / (1 + math.log(idx + 2)) + rng.random() * 0.05)
            for idx, tid in enumerate(picked)
        ]
        scored.sort(key=lambda x: x[1], reverse=True)
        
        return scored[:limit]

    def _get_supplemental_recommendations(
        self, db: Session, user_id: int, exclude_ids: set, limit: int
    ) -> List[int]:
        """
        Get supplemental recommendations based on user's favorite tracks.
        Finds tracks from same artists or similar to user's most played tracks.
        """
        from sqlalchemy import func, desc
        
        # Get user's top played tracks
        top_tracks = (
            db.query(
                Interaction.track_id,
                func.count(Interaction.id).label('play_count')
            )
            .filter(
                Interaction.user_id == user_id,
                Interaction.track_id.isnot(None)
            )
            .group_by(Interaction.track_id)
            .order_by(desc('play_count'))
            .limit(10)
            .all()
        )
        
        if not top_tracks:
            # Fallback to popular tracks
            return self._get_popular_tracks(db, exclude_ids, limit)
        
        favorite_track_ids = [tid for tid, _ in top_tracks if tid]
        
        # Get artists of favorite tracks
        favorite_artists = (
            db.query(Track.artist_id)
            .filter(Track.id.in_(favorite_track_ids))
            .distinct()
            .all()
        )
        artist_ids = [aid[0] for aid in favorite_artists if aid[0]]
        
        if not artist_ids:
            return self._get_popular_tracks(db, exclude_ids, limit)
        
        # Find tracks from same artists that user hasn't heard
        similar_tracks = (
            db.query(Track.id)
            .filter(
                Track.artist_id.in_(artist_ids),
                Track.id.notin_(exclude_ids)
            )
            .limit(limit * 2)
            .all()
        )
        
        result = [tid[0] for tid in similar_tracks if tid[0] not in exclude_ids]
        
        # If not enough, add popular tracks
        if len(result) < limit:
            popular = self._get_popular_tracks(db, exclude_ids | set(result), limit - len(result))
            result.extend(popular)
        
        return result[:limit]

    def _get_popular_tracks(self, db: Session, exclude_ids: set, limit: int) -> List[int]:
        """Get popular tracks excluding specified IDs."""
        from sqlalchemy import func, desc
        
        popular = (
            db.query(Interaction.track_id)
            .filter(
                Interaction.track_id.isnot(None),
                Interaction.track_id.notin_(exclude_ids) if exclude_ids else True
            )
            .group_by(Interaction.track_id)
            .order_by(desc(func.count(Interaction.id)))
            .limit(limit)
            .all()
        )
        
        return [tid[0] for tid in popular if tid[0]]

    def recommend_behavioral(self, db: Session, user_id: int, limit: int = 20) -> List[Tuple[int, float]]:
        """Recommend tracks based only on a single user's listening behavior and likes.

        Scoring heuristic:
        - base play count equivalent = total seconds listened / 30s
        - completed or milestone>=75 get +1 play-equivalent
        - liked tracks get a large boost (+10)
        - final score = play_equiv * plays_weight + like_boost

        This intentionally ignores global popularity and other users.
        """
        from sqlalchemy import func, desc
        # Aggregate interactions for the user
        rows = (
            db.query(
                Interaction.track_id,
                func.coalesce(func.sum(Interaction.seconds_listened), 0).label('seconds'),
                func.coalesce(func.sum(case((Interaction.is_completed == True, 1), else_=0)), 0).label('completed_count'),
                func.coalesce(func.sum(case((Interaction.milestone >= 75, 1), else_=0)), 0).label('milestone_count')
            )
            .filter(Interaction.user_id == user_id, Interaction.track_id.isnot(None))
            .group_by(Interaction.track_id)
            .all()
        )

        # Collect likes
        liked_rows = db.query(TrackLike.track_id).filter(TrackLike.user_id == user_id).all()
        liked_set = {r[0] for r in liked_rows if r[0] is not None}

        scores = []
        seconds_per_equivalent_play = 30.0
        for r in rows:
            tid = int(r[0])
            seconds = float(r[1] or 0.0)
            completed = int(r[2] or 0)
            milestone = int(r[3] or 0)
            play_equiv = seconds / seconds_per_equivalent_play + completed + milestone
            plays_weight = 1.0
            like_boost = 10.0 if tid in liked_set else 0.0
            score = plays_weight * play_equiv + like_boost
            scores.append((tid, float(score)))

        # If no behavior data, fallback to empty list (caller may call cold-start)
        if not scores:
            return []

        # Filter existing tracks and sort
        scores = self._filter_existing_tracks(db, sorted(scores, key=lambda x: x[1], reverse=True))
        return scores[:limit]


# Global instance
ml_recommendation_service = MLRecommendationService()
