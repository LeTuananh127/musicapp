"""Populate Track.external_id from CSV's dzr_sng_id by matching title+artist.

This script attempts to find existing Track rows by title+artist (optionally fuzzy) and
sets Track.external_id = dzr_sng_id when matched and external_id is not already set.

Usage:
  # dry-run sample
  python tools/populate_external_id.py --dry-run --limit 200 --fuzzy --threshold 0.78

  # execute (write DB)
  python tools/populate_external_id.py --execute --limit 5000 --fuzzy --threshold 0.78
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
from app.models.music import Track, Artist
from sqlalchemy import func
import unicodedata
import string
from difflib import SequenceMatcher


def normalize(s: str) -> str:
    if not s:
        return ''
    s = s.strip().lower()
    s = unicodedata.normalize('NFD', s)
    s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
    s = ''.join(ch for ch in s if ch not in string.punctuation)
    return s


def best_fuzzy_artist(name: str, db_artists):
    best = None
    best_score = 0.0
    nname = normalize(name)
    for a in db_artists:
        score = SequenceMatcher(None, nname, normalize(a.name or '')).ratio()
        if score > best_score:
            best_score = score
            best = a
    return best, best_score


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/train.csv')
    p.add_argument('--start', type=int, default=0)
    p.add_argument('--limit', type=int, default=5000)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--fuzzy', action='store_true')
    p.add_argument('--threshold', type=float, default=0.78)
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
            if len(rows) >= args.limit:
                break

    session = SessionLocal()
    try:
        db_artists = None
        if args.fuzzy:
            db_artists = session.query(Artist).all()

        set_count = 0
        skipped = 0
        no_artist = 0
        no_track = 0

        for r in rows:
            dzr = (r.get('dzr_sng_id') or r.get('dzr_id') or r.get('dzr_song_id') or '').strip()
            if not dzr:
                skipped += 1
                continue
            artist_name = (r.get('artist_name') or r.get('artist') or '').strip()
            track_name = (r.get('track_name') or r.get('track') or '').strip()
            if not artist_name or not track_name:
                skipped += 1
                continue

            # try exact artist match
            artist = session.query(Artist).filter(func.lower(Artist.name) == artist_name.lower()).first()
            if not artist and args.fuzzy:
                candidate, score = best_fuzzy_artist(artist_name, db_artists)
                if candidate and score >= args.threshold:
                    artist = candidate

            if not artist:
                no_artist += 1
                continue

            # find track by title exact
            track = session.query(Track).filter(Track.artist_id == artist.id, func.lower(Track.title) == track_name.lower()).first()
            if not track and args.fuzzy:
                tracks_for_artist = session.query(Track).filter(Track.artist_id == artist.id).all()
                best_t = None
                best_ts = 0.0
                ntrack = normalize(track_name)
                for t in tracks_for_artist:
                    s = SequenceMatcher(None, ntrack, normalize(t.title or '')).ratio()
                    if s > best_ts:
                        best_ts = s
                        best_t = t
                if best_t and best_ts >= args.threshold:
                    track = best_t

            if not track:
                no_track += 1
                continue

            if track.external_id:
                skipped += 1
                continue

            if args.execute:
                track.external_id = dzr
                session.add(track)
                set_count += 1
            else:
                set_count += 1

        if args.execute:
            session.commit()

        print(f"Result: processed={len(rows)} set={set_count} skipped={skipped} no_artist={no_artist} no_track={no_track}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
