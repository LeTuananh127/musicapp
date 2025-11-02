"""Enhanced AI-powered recommendation service using Matrix Factorization.

This service loads a trained ALS/MF model and serves personalized recommendations
based on user listening behavior from the interactions table.
"""
import os
import numpy as np
from typing import Optional, List, Tuple
from sqlalchemy.orm import Session
from datetime import datetime, timedelta

from ..models.music import Track, Interaction, UserFeatures


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
        self._load_model()

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

                # Upsert user features
                user_feature = db.query(UserFeatures).filter_by(user_id=int(user_id)).first()
                if user_feature:
                    user_feature.latent_vector = vector_data
                    user_feature.updated_at = datetime.utcnow()
                else:
                    user_feature = UserFeatures(
                        user_id=int(user_id),
                        latent_vector=vector_data,
                        updated_at=datetime.utcnow()
                    )
                    db.add(user_feature)

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


# Global instance
ml_recommendation_service = MLRecommendationService()
