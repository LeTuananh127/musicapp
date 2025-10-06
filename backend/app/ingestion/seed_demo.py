"""Seed demo data for development.

Usage:
    python -m app.ingestion.seed_demo

This script:
  - Inserts a small set of artists, albums, tracks with synthetic audio features.
  - Creates demo users and playlists.
  - Generates random user interaction (listening) logs to support recommendation fallback.

Idempotent behavior: if data already exists (by unique name), it will skip creation.
"""
from __future__ import annotations

import random
from datetime import datetime, timedelta
from typing import Sequence

from sqlalchemy import select, func
from sqlalchemy.orm import Session

from app.core.db import SessionLocal
from app.models.music import Artist, Album, Track, TrackFeature, User, Interaction, Playlist, PlaylistTrack

RNG = random.Random(42)

ARTISTS = [
    {"name": "Lunar Echo"},
    {"name": "Midnight Pulse"},
    {"name": "Neon Valley"},
]

ALBUMS = [
    {"title": "First Light", "artist_index": 0},
    {"title": "Afterglow", "artist_index": 1},
    {"title": "City Dreams", "artist_index": 2},
]

TRACKS = [
    {"title": "Aurora", "album_index": 0, "duration": 210},
    {"title": "Solar Drift", "album_index": 0, "duration": 188},
    {"title": "Night Drive", "album_index": 1, "duration": 240},
    {"title": "Pulsewave", "album_index": 1, "duration": 195},
    {"title": "Skyline", "album_index": 2, "duration": 230},
    {"title": "Rain Neon", "album_index": 2, "duration": 205},
]

USERS = [
    {"username": "alice", "email": "alice@example.com"},
    {"username": "bob", "email": "bob@example.com"},
]

PLAYLISTS = [
    {"name": "Chill Start", "username": "alice", "track_titles": ["Aurora", "Night Drive"]},
    {"name": "Late Focus", "username": "bob", "track_titles": ["Pulsewave", "Skyline"]},
]


def get_or_create(session: Session, model, defaults: dict | None = None, **kwargs):
    stmt = select(model).filter_by(**kwargs)
    instance = session.execute(stmt).scalar_one_or_none()
    if instance:
        return instance, False
    params = {**kwargs, **(defaults or {})}
    instance = model(**params)
    session.add(instance)
    return instance, True


def seed_core(session: Session):
    # Artists
    artist_objs: list[Artist] = []
    for a in ARTISTS:
        artist, created = get_or_create(session, Artist, name=a["name"])
        artist_objs.append(artist)

    # Albums
    album_objs: list[Album] = []
    for alb in ALBUMS:
        artist = artist_objs[alb["artist_index"]]
        album, _ = get_or_create(session, Album, title=alb["title"], artist_id=artist.id, defaults={"release_date": datetime.utcnow().date()})
        album_objs.append(album)

    # Tracks + features
    track_objs: list[Track] = []
    for t in TRACKS:
        album = album_objs[t["album_index"]]
        track, created = get_or_create(
            session,
            Track,
            title=t["title"],
            album_id=album.id,
            defaults={"duration": t["duration"], "genre": RNG.choice(["synthwave", "chill", "electronic"])}
        )
        track_objs.append(track)
        if created:
            # add synthetic feature row
            feat = TrackFeature(
                track=track,
                danceability=RNG.random(),
                energy=RNG.random(),
                valence=RNG.random(),
                tempo=RNG.uniform(80, 140),
            )
            session.add(feat)

    # Users
    user_objs: list[User] = []
    for u in USERS:
        user, created = get_or_create(session, User, username=u["username"], defaults={"email": u["email"], "hashed_password": "dev"})
        user_objs.append(user)

    session.flush()

    # Playlists
    for p in PLAYLISTS:
        owner = next(u for u in user_objs if u.username == p["username"])
        playlist, created = get_or_create(session, Playlist, name=p["name"], owner_id=owner.id)
        if created:
            for title in p["track_titles"]:
                track = next(tr for tr in track_objs if tr.title == title)
                session.add(PlaylistTrack(playlist=playlist, track=track, added_at=datetime.utcnow()))

    # Interactions (random recent listens)
    now = datetime.utcnow()
    for user in user_objs:
        for _ in range(RNG.randint(5, 12)):
            tr = RNG.choice(track_objs)
            listened_at = now - timedelta(minutes=RNG.randint(0, 60 * 24))
            interaction = Interaction(
                user_id=user.id,
                track_id=tr.id,
                listened_at=listened_at,
                play_duration=int(tr.duration * RNG.uniform(0.5, 1.0)) if tr.duration else None,
            )
            session.add(interaction)


def main():
    with SessionLocal() as session:
        seed_core(session)
        session.commit()
    print("Seed data inserted / ensured.")


if __name__ == "__main__":  # pragma: no cover
    main()
