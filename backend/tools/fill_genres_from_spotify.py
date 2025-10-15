"""Fill genres using Spotify as a source (artist-first).

Requires SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET set in environment.

Strategy:
 - For each distinct artist in DB, search Spotify for the artist name.
 - If a match is found, take the artist.genres (list) and pick the first as genre_name.
 - Apply genre_name to all tracks with that artist_id (optionally in --execute).

Usage:
  # dry-run
  python tools\fill_genres_from_spotify.py --dry-run --export-csv tools\spotify_artist_genres_candidates.csv

  # execute
  python tools\fill_genres_from_spotify.py --execute --export-csv tools\spotify_artist_genres_applied.csv
"""
from __future__ import annotations
import argparse
import csv
import os
import sys
import time
import requests

# ensure backend on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.config import get_settings
from app.core.db import SessionLocal
from app.models.music import Track

SETTINGS = get_settings()
SPOTIFY_CLIENT_ID = SETTINGS.spotify_client_id
SPOTIFY_CLIENT_SECRET = SETTINGS.spotify_client_secret

if not SPOTIFY_CLIENT_ID or not SPOTIFY_CLIENT_SECRET:
    raise SystemExit("Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in the environment before running this script.")

AUTH_URL = "https://accounts.spotify.com/api/token"
SEARCH_URL = "https://api.spotify.com/v1/search"

def get_app_token():
    resp = requests.post(AUTH_URL, data={'grant_type':'client_credentials'}, auth=(SPOTIFY_CLIENT_ID, SPOTIFY_CLIENT_SECRET), timeout=10)
    resp.raise_for_status()
    return resp.json().get('access_token')

def search_artist_on_spotify(name: str, token: str):
    params = {'q': name, 'type': 'artist', 'limit': 1}
    headers = {'Authorization': f'Bearer {token}'}
    r = requests.get(SEARCH_URL, params=params, headers=headers, timeout=10)
    if not r.ok:
        return None
    js = r.json()
    items = js.get('artists', {}).get('items', [])
    if not items:
        return None
    return items[0]


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--export-csv', type=str)
    p.add_argument('--sleep', type=float, default=0.2)
    args = p.parse_args()

    token = get_app_token()
    session = SessionLocal()
    try:
        artists = session.query(Track.artist_id, Track.title).distinct().all()
        artist_ids = [a[0] for a in artists]
        print(f"Found {len(artist_ids)} distinct artists")

        rows = []
        artists_with_genre = 0
        will_update = 0

        for aid in artist_ids:
            # find a representative track title to search by artist name: fetch artist name via join is not available easily here
            # We'll attempt to find a track for the artist and use its stored artist_id -> but we don't have artist.name in tracks table
            # So fall back to making a request by artist id string (Spotify search by id is not applicable). Instead, skip if we don't have artist name.
            # TODO: if you have an `artists` table with names, we should use that. Inspecting DB for artists table.
            # Try to get an artist name from `artists` table if exists
            try:
                from app.models.music import Artist
                artist_row = session.query(Artist).filter(Artist.id == aid).first()
                artist_name = artist_row.name if artist_row else None
            except Exception:
                artist_name = None

            if not artist_name:
                rows.append({'artist_id': aid, 'artist_name': '', 'genre_name': '', 'tracks': session.query(Track).filter(Track.artist_id == aid).count()})
                continue

            sp = search_artist_on_spotify(artist_name, token)
            if not sp:
                rows.append({'artist_id': aid, 'artist_name': artist_name, 'genre_name': '', 'tracks': session.query(Track).filter(Track.artist_id == aid).count()})
                time.sleep(args.sleep)
                continue

            genres = sp.get('genres', [])
            genre_name = genres[0] if genres else ''
            rows.append({'artist_id': aid, 'artist_name': artist_name, 'genre_name': genre_name, 'tracks': session.query(Track).filter(Track.artist_id == aid).count()})
            if genre_name:
                artists_with_genre += 1
                will_update += session.query(Track).filter(Track.artist_id == aid).count()
                if args.execute:
                    session.query(Track).filter(Track.artist_id == aid).update({Track.genre_name: genre_name}, synchronize_session=False)

            time.sleep(args.sleep)

        if args.execute:
            session.commit()

        if args.export_csv:
            with open(args.export_csv, 'w', newline='', encoding='utf-8') as fh:
                w = csv.DictWriter(fh, fieldnames=['artist_id','artist_name','genre_name','tracks'])
                w.writeheader()
                for r in rows:
                    w.writerow(r)

        print(f"Artists with genre found: {artists_with_genre}")
        print(f"Total tracks that would be updated: {will_update}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
