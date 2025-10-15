"""Fill genres by artist (artist-first strategy).

For each distinct artist in the DB, call Deezer `/artist/{id}/genres` (or `/artist/{id}` as fallback)
and, if a genre is found, propose assigning it to all tracks with that artist_id.

Usage:
  python fill_genres_by_artist.py --dry-run --export-csv tools\artist_genres_candidates.csv
  python fill_genres_by_artist.py --execute --export-csv tools\artist_genres_applied.csv
"""
from __future__ import annotations
import argparse
import csv
import time
import os
import sys
import requests

# ensure backend on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track

BASE = "https://api.deezer.com"


def get_genre_for_artist(artist_id: int):
    # Try /artist/{id}/genres first
    try:
        r = requests.get(f"{BASE}/artist/{artist_id}/genres", timeout=8)
        if r.ok:
            js = r.json()
            data = js.get('data', [])
            if data:
                return data[0].get('id'), data[0].get('name')
    except Exception:
        pass

    # Fallback: /artist/{id}
    try:
        r2 = requests.get(f"{BASE}/artist/{artist_id}", timeout=8)
        if r2.ok:
            j = r2.json()
            gid = j.get('genre_id')
            if gid:
                g = requests.get(f"{BASE}/genre/{gid}", timeout=6)
                if g.ok:
                    return gid, g.json().get('name')
    except Exception:
        pass

    return None, None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--export-csv', type=str, help='CSV path to write results')
    p.add_argument('--sleep', type=float, default=0.2, help='Sleep seconds between artist API calls')
    args = p.parse_args()

    session = SessionLocal()
    try:
        artists = session.query(Track.artist_id).distinct().all()
        artist_ids = [a[0] for a in artists]
        print(f"Found {len(artist_ids)} distinct artists to scan")

        rows = []
        will_update = 0
        artists_with_genre = 0

        for aid in artist_ids:
            gid, gname = get_genre_for_artist(aid)
            # count tracks for this artist
            count_tracks = session.query(Track).filter(Track.artist_id == aid).count()
            rows.append({'artist_id': aid, 'genre_id': gid or '', 'genre_name': gname or '', 'tracks': count_tracks})
            if gid or gname:
                artists_with_genre += 1
                will_update += count_tracks
                if args.execute:
                    # bulk update tracks for this artist
                    session.query(Track).filter(Track.artist_id == aid).update({Track.genre_id: gid, Track.genre_name: gname}, synchronize_session=False)
            time.sleep(args.sleep)

        if args.execute:
            session.commit()

        if args.export_csv:
            with open(args.export_csv, 'w', newline='', encoding='utf-8') as fh:
                w = csv.DictWriter(fh, fieldnames=['artist_id','genre_id','genre_name','tracks'])
                w.writeheader()
                for r in rows:
                    w.writerow(r)

        print(f"Artists with genre found: {artists_with_genre}")
        print(f"Total tracks that would be updated: {will_update}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
