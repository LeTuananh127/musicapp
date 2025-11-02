"""Export tracks from DB to CSV for preview review.

Outputs: tools/db_tracks_preview_export.csv with columns:
  id,title,artist_id,artist_name,preview_url,cover_url,duration_ms,external_id,valence,arousal

Usage:
  python tools/export_db_tracks_preview.py
"""
from __future__ import annotations
import csv
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track


def main():
    out_path = os.path.join(os.path.dirname(__file__), 'db_tracks_preview_export.csv')
    session = SessionLocal()
    try:
        rows = session.query(Track).all()
        with open(out_path, 'w', newline='', encoding='utf-8') as fh:
            writer = csv.writer(fh)
            writer.writerow(['id', 'title', 'artist_id', 'artist_name', 'preview_url', 'cover_url', 'duration_ms', 'external_id', 'valence', 'arousal'])
            for t in rows:
                aid = t.artist_id
                an = None
                try:
                    an = t.artist.name if t.artist else None
                except Exception:
                    an = None
                writer.writerow([
                    t.id,
                    t.title or '',
                    aid or '',
                    an or '',
                    t.preview_url or '',
                    t.cover_url or '',
                    t.duration_ms or '',
                    t.external_id or '',
                    t.valence if t.valence is not None else '',
                    t.arousal if t.arousal is not None else '',
                ])
    finally:
        session.close()

    print('Exported', out_path)


if __name__ == '__main__':
    main()
