"""
Propagate cover_url from tracks to their album when album.cover_url is missing.

Usage:
  python tools\fill_album_covers_from_tracks.py --dry-run --limit 10000 --export-csv tools/album_cover_updates_sample.csv
  python tools\fill_album_covers_from_tracks.py --execute --batch-size 5000

This is non-destructive when run with --dry-run. When --execute is provided it updates albums in batches and commits.
"""
from __future__ import annotations
import argparse
import os
import sys
from pathlib import Path

# ensure backend root on path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Album, Track
import csv

OUT_DEFAULT = Path(__file__).resolve().parent / 'album_cover_updates_sample.csv'


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--limit', type=int, default=100000, help='Max number of albums to scan')
    p.add_argument('--batch-size', type=int, default=1000, help='Commit every N updates')
    p.add_argument('--export-csv', type=str, default=str(OUT_DEFAULT))
    args = p.parse_args()

    if args.execute and args.dry_run:
        print('Cannot use --execute and --dry-run together')
        return

    session = SessionLocal()
    try:
        # find albums missing cover
        q = session.query(Album).filter((Album.cover_url == None) | (Album.cover_url == "")).limit(args.limit)
        albums = q.all()
        print(f"Scanning {len(albums)} albums with missing cover (limit={args.limit})")

        candidates = []
        updates = 0
        for i, alb in enumerate(albums, start=1):
            # find any track on this album with cover_url
            if not alb.id:
                continue
            track = session.query(Track).filter(Track.album_id == alb.id, (Track.cover_url != None), (Track.cover_url != "")).first()
            if track and track.cover_url:
                candidates.append({'album_id': alb.id, 'album_title': alb.title or '', 'found_cover_url': track.cover_url})
                if args.execute:
                    alb.cover_url = track.cover_url
                    session.add(alb)
                    updates += 1
                    if updates % args.batch_size == 0:
                        session.commit()
            # else no track cover found for this album
        if args.execute:
            session.commit()
            print(f"Updated {updates} albums with cover_url from tracks")
        else:
            print(f"Would update {len(candidates)} albums (dry-run)")

        # export CSV
        if candidates and args.export_csv:
            path = args.export_csv
            with open(path, 'w', newline='', encoding='utf-8') as fh:
                keys = ['album_id','album_title','found_cover_url']
                w = csv.DictWriter(fh, fieldnames=keys)
                w.writeheader()
                for r in candidates:
                    w.writerow(r)
            print(f"Wrote {len(candidates)} candidate rows to {path}")

    finally:
        session.close()


if __name__ == '__main__':
    main()
