"""
Print simple DB stats: counts of artists, albums, tracks.

Usage:
  python tools\count_db_stats.py
"""
from __future__ import annotations
import os
import sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Artist, Album, Track

def main():
    session = SessionLocal()
    try:
        a = session.query(Artist).count()
        b = session.query(Album).count()
        t = session.query(Track).count()
        print(f"artists={a} albums={b} tracks={t}")
    finally:
        session.close()

if __name__ == '__main__':
    main()
