"""
Check how many tracks/albums are missing cover_url and export a CSV sample for review.

Usage:
  python tools\check_cover_urls.py

Outputs:
  - prints counts to stdout
  - writes `tools/missing_covers_sample.csv` with sample rows
"""
from __future__ import annotations
import csv
from pathlib import Path
import os
import sys
# Imports for DB models are performed inside main() after ensuring sys.path includes the backend root.

OUT = Path(__file__).resolve().parent / 'missing_covers_sample.csv'

def main():
    # ensure backend package is importable when script is run from repo root
    ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
    if ROOT not in sys.path:
        sys.path.insert(0, ROOT)
    # re-import SessionLocal now that sys.path is set (imports above may have failed if module not found)
    from app.core.db import SessionLocal as _SessionLocal  # type: ignore
    from app.models.music import Track as _Track, Album as _Album, Artist as _Artist  # type: ignore
    Session = _SessionLocal
    TrackModel = _Track
    AlbumModel = _Album
    ArtistModel = _Artist
    session = Session()
    try:
        total_tracks = session.query(TrackModel).count()
        missing_track_covers = session.query(TrackModel).filter((TrackModel.cover_url == None) | (TrackModel.cover_url == "")).count()
        total_albums = session.query(AlbumModel).count()
        missing_album_covers = session.query(AlbumModel).filter((AlbumModel.cover_url == None) | (AlbumModel.cover_url == "")).count()

        print(f"Tracks total={total_tracks} missing_cover={missing_track_covers}")
        print(f"Albums total={total_albums} missing_cover={missing_album_covers}")

        # export a sample of up to 200 tracks missing cover
        rows = []
        if missing_track_covers:
            q = session.query(TrackModel).filter((TrackModel.cover_url == None) | (TrackModel.cover_url == "")).limit(200).all()
            for t in q:
                artist_name = None
                if t.artist_id:
                    a = session.get(ArtistModel, t.artist_id)
                    artist_name = a.name if a else None
                rows.append({
                    'id': t.id,
                    'title': t.title,
                    'artist': artist_name or '',
                    'preview_url': t.preview_url or '',
                    'album_id': t.album_id or '',
                    'cover_url': t.cover_url or ''
                })
        # write CSV
        if rows:
            with open(OUT, 'w', newline='', encoding='utf-8') as fh:
                keys = ['id','title','artist','preview_url','album_id','cover_url']
                w = csv.DictWriter(fh, fieldnames=keys)
                w.writeheader()
                for r in rows:
                    w.writerow(r)
            print(f"Wrote sample CSV to {OUT} ({len(rows)} rows)")
        else:
            print("No missing track covers to sample")
    finally:
        session.close()

if __name__ == '__main__':
    main()
