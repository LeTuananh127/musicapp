#!/usr/bin/env python3
"""
Prune tracks in the database keeping only the first N tracks (by id).

This script will:
 - Export affected rows to CSV backup files under tools/backups/ (tracks, track_features, playlist_tracks, interactions, track_likes)
 - Delete rows from dependent tables that reference tracks being removed
 - Delete tracks with id > N
 - Optionally drop a column named `spotify1_track_id` from the `tracks` table if it exists

Usage:
  python prune_tracks_keep_first_n.py --keep 21 [--yes] [--drop-spotify-col]

Run this with your backend venv activated. Make a DB backup first.
"""
from __future__ import annotations

import sys
from argparse import ArgumentParser
from pathlib import Path
import csv

# Add backend/ (where the `app` package lives) to sys.path so imports work
backend_dir = Path(__file__).resolve().parents[1]
repo_root = Path(__file__).resolve().parents[2]
# Prefer backend dir first, then repo root for broader imports
sys.path.insert(0, str(backend_dir))
sys.path.insert(0, str(repo_root))

from app.core.db import SessionLocal, engine
from sqlalchemy import text
from app.models.music import Track, TrackFeatures, PlaylistTrack, Interaction, TrackLike, Album


def ensure_backup_dir(p: Path):
    p.mkdir(parents=True, exist_ok=True)


def export_table(session, query, cols, out_path: Path, params: dict | None = None):
    # pass bind params through to the execute call when provided
    rows = session.execute(query, params or {}).mappings().all()
    if not rows:
        return 0
    with out_path.open('w', newline='', encoding='utf8') as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in rows:
            w.writerow({c: r.get(c) for c in cols})
    return len(rows)


def main():
    p = ArgumentParser()
    p.add_argument('--keep', type=int, default=21, help='Keep tracks with id <= this (default 21)')
    p.add_argument('--yes', action='store_true', help='Skip confirmation')
    p.add_argument('--drop-spotify-col', action='store_true', help='Drop tracks.spotify1_track_id column if exists')
    args = p.parse_args()

    keep_n = args.keep
    print(f'Prune tracks: keeping tracks id <= {keep_n}')

    session = SessionLocal()
    backup_dir = Path(__file__).resolve().parents[1] / 'backups'
    ensure_backup_dir(backup_dir)

    # find affected track ids
    to_remove = [r[0] for r in session.execute(text('SELECT id FROM tracks WHERE id > :keep ORDER BY id'), {'keep': keep_n}).all()]
    if not to_remove:
        print('No tracks to remove. Exiting.')
        return 0

    print(f'Found {len(to_remove)} tracks to remove (ids sample: {to_remove[:10]})')

    if not args.yes:
        ok = input('This will DELETE these tracks and dependent rows. Type YES to continue: ')
        if ok.strip() != 'YES':
            print('Aborting.')
            return 1

    # export dependent rows
    print('Exporting affected rows to backups...')
    # interactions
    params = {'keep': keep_n}
    n_inter = export_table(session, text('SELECT * FROM interactions WHERE track_id > :keep'), ['id','user_id','track_id','played_at','seconds_listened','is_completed','device','context_type','milestone'], backup_dir / 'interactions_removed.csv', params)
    n_pltracks = export_table(session, text('SELECT * FROM playlist_tracks WHERE track_id > :keep'), ['playlist_id','track_id','position','added_at'], backup_dir / 'playlist_tracks_removed.csv', params)
    n_feats = export_table(session, text('SELECT * FROM track_features WHERE track_id > :keep'), ['track_id','danceability','energy','valence','tempo','key','mode','acousticness','instrumentalness','liveness','speechiness','loudness','genre','embedding_vector'], backup_dir / 'track_features_removed.csv', params)
    n_likes = export_table(session, text('SELECT * FROM track_likes WHERE track_id > :keep'), ['user_id','track_id','created_at'], backup_dir / 'track_likes_removed.csv', params)
    n_tracks = export_table(session, text('SELECT * FROM tracks WHERE id > :keep'), ['id','title','album_id','artist_id','duration_ms','preview_url','cover_url','is_explicit'], backup_dir / 'tracks_removed.csv', params)

    print(f'Backed up: interactions={n_inter}, playlist_tracks={n_pltracks}, features={n_feats}, likes={n_likes}, tracks={n_tracks}')

    # perform deletions in a transaction
    try:
        with engine.begin() as conn:
            conn.execute(text('DELETE FROM interactions WHERE track_id > :keep'), {'keep': keep_n})
            conn.execute(text('DELETE FROM playlist_tracks WHERE track_id > :keep'), {'keep': keep_n})
            conn.execute(text('DELETE FROM track_likes WHERE track_id > :keep'), {'keep': keep_n})
            conn.execute(text('DELETE FROM track_features WHERE track_id > :keep'), {'keep': keep_n})
            conn.execute(text('DELETE FROM tracks WHERE id > :keep'), {'keep': keep_n})

            if args.drop_spotify_col:
                # Check if column exists
                res = conn.execute(text("SELECT COUNT(*) AS cnt FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'tracks' AND COLUMN_NAME = 'spotify1_track_id'"))
                cnt = res.scalar() if hasattr(res, 'scalar') else list(res)[0]['cnt']
                if cnt and int(cnt) > 0:
                    print('Dropping column tracks.spotify1_track_id')
                    conn.execute(text('ALTER TABLE tracks DROP COLUMN spotify1_track_id'))

        print('Deletion completed successfully.')
        return 0
    except Exception as e:
        print('Error during deletion:', e)
        return 2
    finally:
        session.close()


if __name__ == '__main__':
    raise SystemExit(main())
