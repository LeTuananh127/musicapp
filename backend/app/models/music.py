from __future__ import annotations

from sqlalchemy import String, Integer, ForeignKey, DateTime, Boolean, Float, JSON
from sqlalchemy.orm import Mapped, mapped_column, relationship
from typing import Optional
from datetime import datetime
from ..core.db import Base

class Artist(Base):
    __tablename__ = 'artists'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    name: Mapped[str] = mapped_column(String(255), index=True)
    # optional artist cover image URL
    cover_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # the user who created this artist (nullable)
    created_by: Mapped[int | None] = mapped_column(ForeignKey('users.id'), nullable=True)
    # Use Optional[...] forward reference rather than a quoted union to satisfy SQLAlchemy
    created_by_user: Mapped[Optional["User"]] = relationship('User', backref='created_artists')
    tracks: Mapped[list['Track']] = relationship(back_populates='artist')

class Album(Base):
    __tablename__ = 'albums'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(255), index=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey('artists.id'))
    release_date: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    cover_url: Mapped[str | None] = mapped_column(String(500))
    artist: Mapped[Artist] = relationship(backref='albums')
    tracks: Mapped[list['Track']] = relationship(back_populates='album')

class Track(Base):
    __tablename__ = 'tracks'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    title: Mapped[str] = mapped_column(String(255), index=True)
    album_id: Mapped[int | None] = mapped_column(ForeignKey('albums.id'))
    artist_id: Mapped[int] = mapped_column(ForeignKey('artists.id'))
    duration_ms: Mapped[int]
    preview_url: Mapped[str | None] = mapped_column(String(500))
    cover_url: Mapped[str | None] = mapped_column(String(500))
    views: Mapped[int] = mapped_column(Integer, default=0)
    is_explicit: Mapped[bool] = mapped_column(Boolean, default=False)
    # Mood/emotion features for AI recommendations
    valence: Mapped[float | None] = mapped_column(Float, nullable=True)  # 0.0-1.0: negative to positive mood
    arousal: Mapped[float | None] = mapped_column(Float, nullable=True)  # 0.0-1.0: calm to energetic
    # Deezer / external genre info (nullable)
    genre_id: Mapped[int | None] = mapped_column(Integer, nullable=True)
    genre_name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    album: Mapped[Album | None] = relationship(back_populates='tracks')
    artist: Mapped[Artist] = relationship(back_populates='tracks')
    
    @property
    def artist_name(self) -> str | None:
        """Convenience property so serializers can include artist name directly."""
        try:
            return self.artist.name if self.artist else None
        except Exception:
            return None
    # Use Optional forward ref style to avoid TypeError with '|' on string literal
    # Forward reference must not evaluate union at class creation; use Optional + future annotations
    features: Mapped[Optional["TrackFeatures"]] = relationship(back_populates='track', uselist=False)

class TrackFeatures(Base):
    __tablename__ = 'track_features'
    track_id: Mapped[int] = mapped_column(ForeignKey('tracks.id'), primary_key=True)
    danceability: Mapped[float | None]
    energy: Mapped[float | None]
    valence: Mapped[float | None]
    tempo: Mapped[float | None]
    key: Mapped[int | None]
    mode: Mapped[int | None]
    acousticness: Mapped[float | None]
    instrumentalness: Mapped[float | None]
    liveness: Mapped[float | None]
    speechiness: Mapped[float | None]
    loudness: Mapped[float | None]
    genre: Mapped[str | None] = mapped_column(String(120))
    embedding_vector: Mapped[dict | None] = mapped_column(JSON)
    track: Mapped[Track] = relationship(back_populates='features')

class User(Base):
    __tablename__ = 'users'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    email: Mapped[str] = mapped_column(String(255), unique=True, index=True)
    password_hash: Mapped[str] = mapped_column(String(255))
    display_name: Mapped[str | None] = mapped_column(String(255))
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

class Interaction(Base):
    __tablename__ = 'interactions'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'))
    # internal track id (nullable when recording external plays)
    track_id: Mapped[int | None] = mapped_column(ForeignKey('tracks.id'), nullable=True)
    # Note: we use internal `track_id` for interactions. External provider ids
    # (e.g., Deezer preview ids) were previously tracked in `external_track_id`,
    # but the application now records plays using the internal `track_id` only.
    played_at: Mapped[datetime] = mapped_column(default=datetime.utcnow, index=True)
    seconds_listened: Mapped[int] = mapped_column(Integer, default=0)
    is_completed: Mapped[bool] = mapped_column(Boolean, default=False)
    device: Mapped[str | None] = mapped_column(String(120))
    context_type: Mapped[str | None] = mapped_column(String(120))
    milestone: Mapped[int | None] = mapped_column(Integer, nullable=True, index=True)  # 25,50,75,100

class Playlist(Base):
    __tablename__ = 'playlists'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'))
    name: Mapped[str] = mapped_column(String(255))
    description: Mapped[str | None] = mapped_column(String(500))
    # optional cover image for the playlist (can be provided by client or derived from artist)
    cover_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    is_public: Mapped[bool] = mapped_column(Boolean, default=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

class PlaylistTrack(Base):
    __tablename__ = 'playlist_tracks'
    playlist_id: Mapped[int] = mapped_column(ForeignKey('playlists.id'), primary_key=True)
    track_id: Mapped[int] = mapped_column(ForeignKey('tracks.id'), primary_key=True)
    position: Mapped[int] = mapped_column(Integer, default=0)
    added_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)


class UserPreferredArtist(Base):
    __tablename__ = 'user_preferred_artists'
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), primary_key=True)
    artist_id: Mapped[int] = mapped_column(ForeignKey('artists.id'), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

class Mood(Base):
    __tablename__ = 'moods'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'))
    label: Mapped[str] = mapped_column(String(80))
    confidence: Mapped[float | None]
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    source: Mapped[str | None] = mapped_column(String(50))

class UserFeatures(Base):
    __tablename__ = 'user_features'
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), primary_key=True)
    latent_vector: Mapped[dict | None] = mapped_column(JSON)
    updated_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)

class ModelArtifact(Base):
    __tablename__ = 'model_artifacts'
    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    model_type: Mapped[str] = mapped_column(String(80))
    version: Mapped[str] = mapped_column(String(40))
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
    metrics_json: Mapped[dict | None] = mapped_column(JSON)
    path_or_blob: Mapped[str | None] = mapped_column(String(500))

class TrackLike(Base):
    __tablename__ = 'track_likes'
    user_id: Mapped[int] = mapped_column(ForeignKey('users.id'), primary_key=True)
    track_id: Mapped[int] = mapped_column(ForeignKey('tracks.id'), primary_key=True)
    created_at: Mapped[datetime] = mapped_column(default=datetime.utcnow)
