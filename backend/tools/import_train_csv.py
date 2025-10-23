"""Import tracks from train.csv (Deezer dzr_sng_id -> fetch metadata -> insert into DB).

CSV expected columns: dzr_sng_id,MSD_sng_id,MSD_track_id,valence,arousal,artist_name,track_name

Behavior:
 - For each row: if dzr_sng_id present, call Deezer API /track/{id} to get preview_url, duration_ms, album title, cover.
 - Create Artist if not exists (by name).
 - Create Album if not exists (by title+artist).
 - Create Track if not exists (by title + artist_id). Set preview_url to Deezer preview (if found).

Usage:
  # dry-run sample
  python tools\import_train_csv.py --dry-run --limit 200 --export-csv tools\import_train_sample.csv

  # execute (after review)
  python tools\import_train_csv.py --execute --limit 5000
"""
from __future__ import annotations
import argparse
import csv
import os
import sys
import time
from typing import Optional
import requests

# ensure backend on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Artist, Album, Track

DEEZER_BASE = 'https://api.deezer.com'


def fetch_deezer_track(dzr_id: str) -> Optional[dict]:
    try:
        r = requests.get(f"{DEEZER_BASE}/track/{dzr_id}", timeout=8)
        if not r.ok:
            return None
        return r.json()
    except Exception:
        return None


def find_or_create_artist(session, name: str) -> Artist:
    a = session.query(Artist).filter(Artist.name == name).first()
    if a:
        return a
    a = Artist(name=name)
    session.add(a)
    session.flush()
    return a


def find_or_create_album(session, title: str, artist_id: int) -> Album:
    alb = session.query(Album).filter(Album.title == title, Album.artist_id == artist_id).first()
    if alb:
        return alb
    alb = Album(title=title, artist_id=artist_id)
    session.add(alb)
    session.flush()
    return alb


def track_exists(session, title: str, artist_id: int) -> bool:
    return session.query(Track).filter(Track.title == title, Track.artist_id == artist_id).count() > 0


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/train.csv')
    p.add_argument('--start', type=int, default=0)
    p.add_argument('--limit', type=int, default=500)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--export-csv', type=str, default='tools/import_train_output.csv')
    p.add_argument('--batch-size', type=int, default=1000, help='Commit every N creations when --execute')
    p.add_argument('--sleep', type=float, default=0.12)
    args = p.parse_args()

    if args.execute and args.dry_run:
        print('Cannot use --execute and --dry-run together')
        return

    path = args.csv
    if not os.path.exists(path):
        print('CSV not found:', path)
        return

    rows = []
    with open(path, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        for i, r in enumerate(rd):
            if i < args.start:
                continue
            rows.append(r)
            if len(rows) >= args.limit:
                break

    session = SessionLocal()
    try:
        created_artists = 0
        created_albums = 0
        created_tracks = 0
        failed = 0
        output_rows = []

        ops_since_commit = 0
        for r in rows:
            dzr = r.get('dzr_sng_id') or r.get('dzr_song_id') or ''
            artist_name = (r.get('artist_name') or '').strip()
            track_name = (r.get('track_name') or '').strip()
            if not dzr:
                failed += 1
                output_rows.append({'dzr': '', 'artist': artist_name, 'title': track_name, 'status': 'no_dzr'})
                continue

            # call Deezer
            dj = fetch_deezer_track(dzr)
            time.sleep(args.sleep)
            if not dj or dj.get('error'):
                failed += 1
                output_rows.append({'dzr': dzr, 'artist': artist_name, 'title': track_name, 'status': 'deezer_not_found'})
                continue

            # use metadata from Deezer where available
            d_title = dj.get('title') or track_name
            d_duration = int(dj.get('duration')) * 1000 if dj.get('duration') else None
            preview = dj.get('preview')
            album_obj = dj.get('album') or {}
            album_title = album_obj.get('title') or None
            cover = album_obj.get('cover') or None

            # find/create artist
            if not artist_name:
                # fallback to deezer artist name
                artist_name = (dj.get('artist') or {}).get('name')

            artist = session.query(Artist).filter(Artist.name == artist_name).first()
            if not artist:
                if not args.dry_run:
                    artist = Artist(name=artist_name)
                    session.add(artist)
                    session.flush()
                    ops_since_commit += 1
                created_artists += 1
            else:
                created_artists += 0

            artist_id = artist.id if artist else None

            # album
            album = None
            if album_title and artist_id:
                album = session.query(Album).filter(Album.title == album_title, Album.artist_id == artist_id).first()
                if not album:
                    if not args.dry_run:
                        album = Album(title=album_title, artist_id=artist_id, cover_url=cover)
                        session.add(album)
                        session.flush()
                        ops_since_commit += 1
                    created_albums += 1

            # track exists?
            exists = False
            if artist_id and d_title:
                exists = track_exists(session, d_title, artist_id)

            if exists:
                output_rows.append({'dzr': dzr, 'artist': artist_name, 'title': d_title, 'status': 'exists'})
                continue

            # create track
            if not args.dry_run:
                t = Track(title=d_title, artist_id=artist_id, album_id=album.id if album else None, duration_ms=d_duration or 0, preview_url=preview, cover_url=cover, is_explicit=False)
                session.add(t)
                session.flush()
                created_tracks += 1
                ops_since_commit += 1
                output_rows.append({'dzr': dzr, 'artist': artist_name, 'title': d_title, 'status': 'created', 'preview': preview or ''})
                # commit per batch to avoid long-running transactions
                if args.batch_size and ops_since_commit >= args.batch_size:
                    session.commit()
                    ops_since_commit = 0
            else:
                output_rows.append({'dzr': dzr, 'artist': artist_name, 'title': d_title, 'status': 'would_create', 'preview': preview or ''})

        if args.execute:
            # commit any remaining operations
            try:
                session.commit()
            except Exception:
                session.rollback()
                raise

        # export CSV
        if args.export_csv:
            # compute union of all keys across output rows to avoid missing-field errors
            if output_rows:
                all_keys = []
                seen = set()
                for orow in output_rows:
                    for k in orow.keys():
                        if k not in seen:
                            seen.add(k)
                            all_keys.append(k)
                keys = all_keys
            else:
                keys = ['dzr', 'artist', 'title', 'status']
            with open(args.export_csv, 'w', newline='', encoding='utf-8') as fh:
                w = csv.DictWriter(fh, fieldnames=keys)
                w.writeheader()
                for orow in output_rows:
                    # ensure all keys exist (csv.DictWriter will fill missing with '')
                    w.writerow({k: orow.get(k, '') for k in keys})

        print(f"Summary: rows_processed={len(rows)} created_artists={created_artists} created_albums={created_albums} created_tracks={created_tracks} failed={failed}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
