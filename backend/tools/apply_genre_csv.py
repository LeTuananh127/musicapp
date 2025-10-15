"""Apply genre updates from a CSV to the `tracks` table.

CSV formats supported:
- If CSV has a header column `id` -> will update track rows by id, using `genre_id` and/or `genre_name` columns.
- Else if CSV has `artist_id` and `genre_name` -> will update all tracks with that artist_id.

Usage:
  # dry-run (no DB writes)
  python tools\apply_genre_csv.py --csv tools\preview_genres_applied.csv --dry-run

  # execute updates
  python tools\apply_genre_csv.py --csv tools\preview_genres_applied.csv --execute
"""
from __future__ import annotations
import argparse
import csv
import os
import sys

# ensure backend on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', required=True)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    args = p.parse_args()

    path = args.csv
    if not os.path.exists(path):
        print(f'CSV not found: {path}')
        return

    with open(path, newline='', encoding='utf-8') as fh:
        r = csv.DictReader(fh)
        rows = list(r)

    session = SessionLocal()
    try:
        updates = 0
        skipped = 0
        for row in rows:
            # if 'id' present, update by track id
            if 'id' in row and row['id'].strip():
                tid = int(row['id'])
                genre_id = row.get('genre_id') or None
                genre_name = row.get('genre_name') or None
                if genre_id == '':
                    genre_id = None
                if genre_name == '':
                    genre_name = None
                track = session.query(Track).get(tid)
                if not track:
                    skipped += 1
                    continue
                # compare current values
                cur_gid = getattr(track, 'genre_id', None)
                cur_gname = getattr(track, 'genre_name', None)
                if (genre_id is None or genre_id == '') and (genre_name is None or genre_name == ''):
                    skipped += 1
                    continue
                print(f"Will update track id={tid}: genre_id {cur_gid} -> {genre_id}, genre_name {cur_gname} -> {genre_name}")
                if args.execute:
                    # set values
                    track.genre_id = int(genre_id) if genre_id else None
                    track.genre_name = genre_name
                    session.add(track)
                    updates += 1
            elif 'artist_id' in row and row.get('genre_name'):
                aid = int(row['artist_id'])
                gname = row['genre_name'] or None
                ct = session.query(Track).filter(Track.artist_id == aid).count()
                print(f"Will update {ct} tracks for artist_id={aid} -> genre_name='{gname}'")
                if args.execute:
                    session.query(Track).filter(Track.artist_id == aid).update({Track.genre_name: gname}, synchronize_session=False)
                    updates += ct
            else:
                skipped += 1

        if args.execute:
            session.commit()

        print(f"Summary: rows={len(rows)} updates={updates} skipped={skipped}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
