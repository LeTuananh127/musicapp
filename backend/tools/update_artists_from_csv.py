"""Update Artist.cover_url from a CSV export (e.g. tools/import_train_output.csv).

Reads CSV rows with columns including 'artist' and 'artist_pic' (or tries common alternatives).
For each row it will find the Artist by exact (case-sensitive) name match, or case-insensitive
match as fallback, and set `cover_url` when a URL is present. By default it will only set when
the DB value is empty; use --force to overwrite existing values.

Usage:
  python tools/update_artists_from_csv.py --csv tools/import_train_output.csv --dry-run --limit 200
  python tools/update_artists_from_csv.py --csv tools/import_train_output.csv --execute --force
"""
from __future__ import annotations
import csv
import os
import sys
import argparse
from typing import Optional

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Artist
from sqlalchemy import func


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/import_train_output.csv')
    p.add_argument('--start', type=int, default=0)
    p.add_argument('--limit', type=int, default=0)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--force', action='store_true', help='Overwrite existing artist.cover_url when provided')
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
            if args.limit and len(rows) >= args.limit:
                break

    session = SessionLocal()
    try:
        updated = 0
        skipped = 0
        not_found = 0

        def try_get_artist_pic(r: dict) -> Optional[str]:
            # common field names
            for k in ('artist_pic', 'artist_cover', 'artist_picture', 'artist_img', 'artist_image'):
                if r.get(k):
                    return (r.get(k) or '').strip()
            # sometimes import CSV includes 'preview' or 'cover' for track; not ideal but check
            for k in ('artist',):
                pass
            return None

        for r in rows:
            artist_name = (r.get('artist') or r.get('artist_name') or '').strip()
            if not artist_name:
                not_found += 1
                continue
            pic = try_get_artist_pic(r)
            if not pic:
                skipped += 1
                continue

            # prefer exact match
            artist = session.query(Artist).filter(Artist.name == artist_name).first()
            if not artist:
                # fallback case-insensitive
                artist = session.query(Artist).filter(func.lower(Artist.name) == artist_name.lower()).first()
            if not artist:
                not_found += 1
                continue

            # decide whether to update
            current = getattr(artist, 'cover_url', None)
            if current and not args.force:
                skipped += 1
                continue

            print(f"Will update artist id={artist.id} name='{artist.name}' cover: '{current}' -> '{pic}'")
            if args.execute and not args.dry_run:
                artist.cover_url = pic
                session.add(artist)
                updated += 1

        if args.execute and not args.dry_run:
            session.commit()

        print(f"Summary: rows_processed={len(rows)} updated={updated} skipped_no_pic={skipped} not_found={not_found}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
