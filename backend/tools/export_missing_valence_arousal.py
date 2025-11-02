"""Export tracks missing valence or arousal to CSV.

Writes to tools/missing_valence_arousal_export.csv with columns:
id,title,artist_id,artist_name,external_id,preview_url,cover_url,valence,arousal
"""
from __future__ import annotations
import os
import csv
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track


def main():
    session = SessionLocal()
    try:
        qry = session.query(Track).filter((Track.valence == None) | (Track.arousal == None)).all()
        out = os.path.join(os.path.dirname(__file__), 'missing_valence_arousal_export.csv')
        with open(out, 'w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['id','title','artist_id','artist_name','external_id','preview_url','cover_url','valence','arousal'])
            for t in qry:
                artist_name = t.artist.name if t.artist else ''
                w.writerow([
                    t.id,
                    t.title or '',
                    t.artist_id or '',
                    artist_name,
                    t.external_id or '',
                    t.preview_url or '',
                    t.cover_url or '',
                    '' if t.valence is None else t.valence,
                    '' if t.arousal is None else t.arousal,
                ])
        print('Exported', out, 'rows=', len(qry))
    finally:
        session.close()


if __name__ == '__main__':
    main()
