"""Update valence and arousal for existing Tracks from a CSV.

Behavior:
 - Reads CSV (default: tools/train.csv)
 - For each row, extracts artist_name, track_name, valence, arousal
 - Finds existing Track by title + artist (case-insensitive). If found and valence/arousal provided
   in CSV, updates the Track record (only these two fields).

Usage:
  # dry-run (no DB writes), sample 200 rows
  python tools/update_valence_arousal.py --dry-run --limit 200

  # execute for all rows
  python tools/update_valence_arousal.py --execute

Assumptions:
 - Matching is done by title + artist name (case-insensitive). If you prefer matching by an external id,
   provide that mapping or ask me to change the script to upsert by external id.
"""
from __future__ import annotations
import csv
import os
import sys
import argparse
from typing import Optional

# ensure backend path
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track, Artist
from sqlalchemy import func
import unicodedata
import string
from difflib import SequenceMatcher


def parse_float(s: str) -> Optional[float]:
    if s is None or s == '':
        return None
    try:
        return float(s)
    except Exception:
        return None


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/train.csv')
    p.add_argument('--start', type=int, default=0)
    p.add_argument('--limit', type=int, default=5000)
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--batch-size', type=int, default=500)
    p.add_argument('--fuzzy', action='store_true', help='Enable fuzzy matching for artist/title when exact match fails')
    p.add_argument('--threshold', type=float, default=0.82, help='Fuzzy match threshold (0-1)')
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
        updated = 0
        skipped = 0
        not_found = 0
        ops = 0

        # preload artist list for fuzzy matching
        db_artists = None
        if args.fuzzy:
            db_artists = session.query(Artist).all()

        def normalize(s: str) -> str:
            if not s:
                return ''
            s = s.strip().lower()
            # remove accents
            s = unicodedata.normalize('NFD', s)
            s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
            # remove punctuation
            s = ''.join(ch for ch in s if ch not in string.punctuation)
            return s

        def best_fuzzy_artist(name: str):
            if not db_artists:
                return None, 0.0
            best = None
            best_score = 0.0
            nname = normalize(name)
            for a in db_artists:
                score = SequenceMatcher(None, nname, normalize(a.name or '')).ratio()
                if score > best_score:
                    best_score = score
                    best = a
            return best, best_score

        for r in rows:
            artist_name = (r.get('artist_name') or r.get('artist') or '').strip()
            track_name = (r.get('track_name') or r.get('track') or '').strip()
            if not artist_name or not track_name:
                skipped += 1
                continue

            val = parse_float(r.get('valence'))
            aro = parse_float(r.get('arousal'))
            if val is None and aro is None:
                skipped += 1
                continue

            # prefer matching by external id (Deezer id) if present in CSV
            dzr = (r.get('dzr_sng_id') or r.get('dzr_id') or r.get('dzr_song_id') or '').strip()
            track = None
            artist = None
            if dzr:
                track = session.query(Track).filter(Track.external_id == dzr).first()
                if track:
                    artist = session.query(Artist).filter(Artist.id == track.artist_id).first()

            # find artist case-insensitive as fallback
            used_fuzzy = False
            fuzzy_score = 0.0
            if not artist:
                artist = session.query(Artist).filter(func.lower(Artist.name) == artist_name.lower()).first()
                if not artist and args.fuzzy:
                    candidate, fuzzy_score = best_fuzzy_artist(artist_name)
                    if candidate and fuzzy_score >= args.threshold:
                        artist = candidate
                        used_fuzzy = True
            if not artist:
                not_found += 1
                continue

            if not track:
                track = session.query(Track).filter(Track.artist_id == artist.id, func.lower(Track.title) == track_name.lower()).first()
            if not track and args.fuzzy and artist:
                # fuzzy match track title within this artist's tracks
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
                    used_fuzzy = True
            if not track:
                not_found += 1
                continue

            changed = False
            if val is not None and (track.valence is None or abs((track.valence or 0.0) - val) > 1e-6):
                if not args.dry_run:
                    track.valence = val
                changed = True
            if aro is not None and (track.arousal is None or abs((track.arousal or 0.0) - aro) > 1e-6):
                if not args.dry_run:
                    track.arousal = aro
                changed = True

            if changed:
                updated += 1
                ops += 1
                if dzr and track and not track.external_id and args.execute:
                    try:
                        track.external_id = dzr
                    except Exception:
                        pass
                if not args.dry_run:
                    session.add(track)
                # commit per batch
                if ops >= args.batch_size:
                    if not args.dry_run:
                        session.commit()
                    ops = 0
            else:
                skipped += 1

        # final commit
        if not args.dry_run and ops > 0:
            session.commit()

        print(f"Summary: rows_processed={len(rows)} updated={updated} skipped={skipped} not_found={not_found}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
