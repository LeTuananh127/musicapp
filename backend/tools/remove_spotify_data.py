#!/usr/bin/env python3
"""
Safe helper to remove Spotify-related URL/data from the application's database.

This script will null out any `preview_url` values on `tracks` and will null
out `cover_url` fields on `tracks` and `albums` when they appear to reference
Spotify (contain 'spotify' or 'open.spotify.com'). It reports counts before
and after, and requires confirmation unless run with --yes.

Usage:
  python remove_spotify_data.py [--yes]

Run from repository root (backend/) with your virtualenv activated so project
dependencies and DB access are available.

Important: make a DB backup (mysqldump or similar) before running if you need
to be able to restore.
"""
from __future__ import annotations

import sys
from argparse import ArgumentParser

# Ensure repo root is importable when invoked from backend/tools
from pathlib import Path
root = Path(__file__).resolve().parents[2]
backend_dir = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(backend_dir))
sys.path.insert(0, str(root))

from app.core.db import SessionLocal
from app.models.music import Track, Album


def count_and_preview(session):
    cnt_preview = session.query(Track).filter(Track.preview_url != None).count()
    cnt_track_covers = session.query(Track).filter(Track.cover_url != None).filter(Track.cover_url.ilike('%spotify%')).count()
    cnt_album_covers = session.query(Album).filter(Album.cover_url != None).filter(Album.cover_url.ilike('%spotify%')).count()
    return cnt_preview, cnt_track_covers, cnt_album_covers


def main():
    p = ArgumentParser()
    p.add_argument('--yes', action='store_true', help='Skip confirmation prompt')
    args = p.parse_args()

    print('Connecting to database...')
    session = SessionLocal()
    try:
        preview_count, track_covers_count, album_covers_count = count_and_preview(session)
        print('\nThis will perform the following changes:')
        print(f' - Null out preview_url on tracks (currently non-null rows: {preview_count})')
        print(f" - Null out track.cover_url values containing 'spotify' (rows: {track_covers_count})")
        print(f" - Null out album.cover_url values containing 'spotify' (rows: {album_covers_count})")

        if preview_count + track_covers_count + album_covers_count == 0:
            print('\nNo Spotify-like data detected. Nothing to do.')
            return 0

        if not args.yes:
            resp = input('\nProceed with deletion (type YES to continue)? ')
            if resp.strip() != 'YES':
                print('Aborting — no changes made.')
                return 1

        # perform updates in a transaction
        with session.begin():
            # Null preview_url on tracks
            if preview_count:
                session.query(Track).filter(Track.preview_url != None).update({Track.preview_url: None}, synchronize_session=False)
            # Null cover_url fields that reference spotify
            if track_covers_count:
                session.query(Track).filter(Track.cover_url != None).filter(Track.cover_url.ilike('%spotify%')).update({Track.cover_url: None}, synchronize_session=False)
            if album_covers_count:
                session.query(Album).filter(Album.cover_url != None).filter(Album.cover_url.ilike('%spotify%')).update({Album.cover_url: None}, synchronize_session=False)

        # report final counts
        preview_count2, track_covers_count2, album_covers_count2 = count_and_preview(session)
        print('\nCompleted. Remaining counts:')
        print(f' - preview_url non-null rows: {preview_count2}')
        print(f" - track.cover_url containing 'spotify': {track_covers_count2}")
        print(f" - album.cover_url containing 'spotify': {album_covers_count2}")
        return 0

    finally:
        session.close()


if __name__ == '__main__':
    raise SystemExit(main())
