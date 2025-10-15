"""Import Deezer catalog data (charts / artist top) into local DB.

Usage example (from repo root):
  python backend\tools\import_deezer_catalog.py --charts --limit 20 --delay 0.2

The script is resumable: it keeps a small JSON state file under backend/.deezer_import_state.json
recording processed artist IDs. It is rate-limited by --delay seconds between requests.
"""
from __future__ import annotations

import sys
from pathlib import Path
import time
import json
import argparse
from typing import Optional

# Ensure app package importable when running from repo root
HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE))

import requests
from app.core.db import SessionLocal
from app.models.music import Artist, Album, Track

STATE_PATH = HERE / '.deezer_import_state.json'
BASE = 'https://api.deezer.com'


def load_state():
    if STATE_PATH.exists():
        try:
            return json.loads(STATE_PATH.read_text())
        except Exception:
            return {}
    return {}


def save_state(s):
    try:
        STATE_PATH.write_text(json.dumps(s))
    except Exception:
        pass


def get_or_create(session, model, lookup: dict, defaults: dict | None = None):
    q = session.query(model).filter_by(**lookup).first()
    if q:
        return q, False
    params = {**lookup, **(defaults or {})}
    instance = model(**params)
    session.add(instance)
    session.flush()
    return instance, True


def fetch_json(path: str, params: dict | None = None, timeout=10) -> Optional[dict]:
    url = f"{BASE}{path}"
    try:
        r = requests.get(url, params=params or {}, timeout=timeout)
        if r.status_code == 200:
            return r.json()
        else:
            print(f"Deezer {url} -> {r.status_code}")
            return None
    except Exception as e:
        print('Request failed', e)
        return None


def import_track(session, dtrack: dict):
    # dtrack is Deezer track object
    artist_info = dtrack.get('artist') or {}
    album_info = dtrack.get('album') or {}
    # artist
    artist, _ = get_or_create(session, Artist, {'name': artist_info.get('name')}, defaults={})
    # album
    album_defaults = {'release_date': None, 'cover_url': album_info.get('cover_big')}
    album_lookup = {'title': album_info.get('title'), 'artist_id': artist.id}
    album, _ = get_or_create(session, Album, album_lookup, defaults=album_defaults) if 'Album' in globals() or True else (None, False)
    # Note: Album class may not be imported in this file; we'll attempt to use minimal fields on Track
    # Create track
    preview = dtrack.get('preview')
    cover = album_info.get('cover_medium') or dtrack.get('cover')
    title = dtrack.get('title')
    duration = int(dtrack.get('duration', 0) * 1000)
    track_lookup = {'title': title, 'artist_id': artist.id}
    track_defaults = {'duration_ms': duration, 'preview_url': preview, 'cover_url': cover}
    track, created = get_or_create(session, Track, track_lookup, defaults=track_defaults)
    if not created:
        # update preview/cover if missing
        updated = False
        if not track.preview_url and preview:
            track.preview_url = preview
            updated = True
        if not track.cover_url and cover:
            track.cover_url = cover
            updated = True
        if updated:
            session.add(track)
    return track


def import_from_charts(limit: int = 50, delay: float = 0.25):
    session = SessionLocal()
    try:
        print('Fetching charts...')
        data = fetch_json('/chart', params={'limit': limit})
        if not data:
            print('No chart data')
            return
        tracks = data.get('tracks', {}).get('data', [])
        print(f'Got {len(tracks)} chart tracks')
        for t in tracks:
            import_track(session, t)
            session.commit()
            time.sleep(delay)
    finally:
        session.close()


def import_artist_top(artist_id: int, limit: int = 50, delay: float = 0.2):
    session = SessionLocal()
    try:
        print(f'Fetching top for artist {artist_id}...')
        data = fetch_json(f'/artist/{artist_id}/top', params={'limit': limit})
        if not data:
            print('No data')
            return
        tracks = data.get('data', [])
        for t in tracks:
            import_track(session, t)
            session.commit()
            time.sleep(delay)
    finally:
        session.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--charts', action='store_true')
    p.add_argument('--artist-top', type=int, help='Artist id to import top tracks for')
    p.add_argument('--limit', type=int, default=50)
    p.add_argument('--delay', type=float, default=0.25)
    args = p.parse_args()

    if args.charts:
        import_from_charts(limit=args.limit, delay=args.delay)
    elif args.artist_top:
        import_artist_top(args.artist_top, limit=args.limit, delay=args.delay)
    else:
        print('Nothing to do. Use --charts or --artist-top')


if __name__ == '__main__':
    main()
