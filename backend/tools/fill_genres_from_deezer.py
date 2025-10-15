"""Fill `genre_id` and `genre_name` on `tracks` by querying Deezer API.

Usage:
  python fill_genres_from_deezer.py --dry-run --limit 500
  python fill_genres_from_deezer.py --execute --limit 500

The script will, per track:
 - call Deezer /track/{id} to read album.genre_id if present
 - if not present, call /artist/{id}/genres and take first genre
 - write to tracks.genre_id and tracks.genre_name when found
"""

from __future__ import annotations
import argparse
import csv
import time
from typing import Optional
import os
import sys
import requests

# Ensure backend/ is on sys.path so 'app' package imports work when running tools
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track

BASE = "https://api.deezer.com"


def get_genre_from_track(track_id: int) -> tuple[Optional[int], Optional[str]]:
    try:
        r = requests.get(f"{BASE}/track/{track_id}", timeout=8)
        r.raise_for_status()
        j = r.json()
    except Exception as e:
        return None, None

    # 1) album.genre_id
    album = j.get('album') or {}
    gid = album.get('genre_id')
    if gid:
        g = requests.get(f"{BASE}/genre/{gid}", timeout=6)
        if g.ok:
            return gid, g.json().get('name')

    # 2) artist -> /artist/{id}/genres
    artist = j.get('artist') or {}
    aid = artist.get('id')
    if aid:
        gr = requests.get(f"{BASE}/artist/{aid}/genres", timeout=8)
        if gr.ok:
            data = gr.json().get('data', [])
            if data:
                return data[0].get('id'), data[0].get('name')

        # fallback: artist endpoint
        ar2 = requests.get(f"{BASE}/artist/{aid}", timeout=6)
        if ar2.ok:
            aj = ar2.json()
            if aj.get('genre_id'):
                gg = requests.get(f"{BASE}/genre/{aj['genre_id']}")
                if gg.ok:
                    return aj['genre_id'], gg.json().get('name')

    return None, None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--limit', type=int, default=500)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--export-csv', type=str, help='Write CSV of findings')
    args = p.parse_args()

    session = SessionLocal()
    try:
        tracks = session.query(Track).limit(args.limit).all()
        out_rows = []
        updated = 0
        for t in tracks:
            gid, gname = get_genre_from_track(t.id)
            out_rows.append({'id': t.id, 'title': t.title, 'artist_id': t.artist_id, 'genre_id': gid, 'genre_name': gname})
            if gid or gname:
                if args.execute:
                    t.genre_id = gid
                    t.genre_name = gname
                    session.add(t)
                    updated += 1
                else:
                    # dry-run: just report
                    pass
            time.sleep(0.2)

        if args.execute:
            session.commit()
        if args.export_csv:
            with open(args.export_csv, 'w', newline='', encoding='utf-8') as fh:
                w = csv.DictWriter(fh, fieldnames=['id','title','artist_id','genre_id','genre_name'])
                w.writeheader()
                for r in out_rows:
                    w.writerow(r)

        print(f"Scanned {len(tracks)} tracks. Updated (if executed): {updated}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
