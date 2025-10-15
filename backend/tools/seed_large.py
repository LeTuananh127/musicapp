"""Large data seeder for development/testing.

Usage (from repo root):
    python backend/tools/seed_large.py --artists 50 --tracks-per-artist 100 --users 1000 --interactions-per-user 100 --batch 1000

This script uses SQLAlchemy bulk operations and commits in batches to avoid memory blowup.
"""
from __future__ import annotations

import sys
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
# Ensure backend package (app) is importable when running script directly
sys.path.insert(0, str(ROOT))

import argparse
import random
from datetime import datetime, timedelta
from typing import List

from app.core.db import SessionLocal
from app.core.security import hash_password
from app.models.music import Artist, Track, User, Interaction

RNG = random.Random(12345)


def chunked(iterable, size):
    it = iter(iterable)
    while True:
        chunk = []
        try:
            for _ in range(size):
                chunk.append(next(it))
        except StopIteration:
            if chunk:
                yield chunk
            break
        yield chunk


def seed(artists: int, tracks_per_artist: int, users: int, interactions_per_user: int, batch: int):
    db = SessionLocal()
    try:
        print(f"Seeding {artists} artists, {tracks_per_artist} tracks/artist -> {artists * tracks_per_artist} tracks")
        print(f"Seeding {users} users and ~{users * interactions_per_user} interactions")

        # Artists
        artist_objs: List[Artist] = []
        for i in range(artists):
            artist_objs.append(Artist(name=f"Artist {i+1:05d}"))
        for chunk in chunked(artist_objs, batch):
            db.bulk_save_objects(chunk)
            db.commit()

        # Refresh artist ids
        db.expire_all()
        artist_rows = db.query(Artist).order_by(Artist.id).all()

        # Tracks
        track_objs: List[Track] = []
        for a in artist_rows:
            for j in range(tracks_per_artist):
                t = Track(
                    title=f"Track {a.id}-{j+1:04d}",
                    artist_id=a.id,
                    duration_ms=180000,
                    preview_url=None,
                )
                track_objs.append(t)
        print(f"Generated {len(track_objs)} track objects, inserting in batches...")
        for chunk in chunked(track_objs, batch):
            db.bulk_save_objects(chunk)
            db.commit()

        # Users
        user_objs: List[User] = []
        for u in range(users):
            email = f"user{u+1:06d}@example.local"
            user_objs.append(User(email=email, password_hash=hash_password('secret123'), display_name=f"User{u+1:06d}"))
        print(f"Inserting {len(user_objs)} users...")
        for chunk in chunked(user_objs, batch):
            db.bulk_save_objects(chunk)
            db.commit()

        # Refresh track and user lists
        db.expire_all()
        all_tracks = db.query(Track).all()
        all_users = db.query(User).all()

        # Interactions: generate random listens per user
        print("Generating interactions (will insert in batches)...")
        interaction_objs: List[Interaction] = []
        now = datetime.utcnow()
        for u in all_users:
            for k in range(interactions_per_user):
                tr = RNG.choice(all_tracks)
                listened_at = now - timedelta(seconds=RNG.randint(0, 60 * 60 * 24 * 30))
                inter = Interaction(
                    user_id=u.id,
                    track_id=tr.id,
                    played_at=listened_at,
                    seconds_listened=RNG.randint(5, min(180, tr.duration_ms // 1000)),
                    is_completed=RNG.random() < 0.2,
                )
                interaction_objs.append(inter)
                # flush periodically to avoid memory
                if len(interaction_objs) >= batch:
                    db.bulk_save_objects(interaction_objs)
                    db.commit()
                    interaction_objs = []

        if interaction_objs:
            db.bulk_save_objects(interaction_objs)
            db.commit()

        print("Seeding completed.")
    finally:
        db.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--artists', type=int, default=10)
    p.add_argument('--tracks-per-artist', type=int, default=10)
    p.add_argument('--users', type=int, default=50)
    p.add_argument('--interactions-per-user', type=int, default=20)
    p.add_argument('--batch', type=int, default=1000)
    args = p.parse_args()
    seed(args.artists, args.tracks_per_artist, args.users, args.interactions_per_user, args.batch)


if __name__ == '__main__':
    main()
