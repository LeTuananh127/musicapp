"""Fill missing valence/arousal in DB by looking up values from CSV.

Strategy:
 - Load CSV into maps by deezer id and by normalized (artist|title).
 - For each Track with missing valence or arousal, try to fill from CSV by:
     1) external_id match (dzr id)
     2) exact normalized title+artist match
     3) optional fuzzy match against normalized keys

Usage:
  # dry-run
  python tools/fill_missing_valence.py --dry-run --limit 1000

  # execute
  python tools/fill_missing_valence.py --execute
"""
from __future__ import annotations
import csv
import os
import sys
import argparse
from typing import Optional, Tuple

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track
from sqlalchemy import or_
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


def normalize(s: str) -> str:
    if not s:
        return ''
    s = s.strip().lower()
    s = unicodedata.normalize('NFD', s)
    s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
    s = ''.join(ch for ch in s if ch not in string.punctuation)
    return s


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/train.csv')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--fuzzy', action='store_true')
    p.add_argument('--threshold', type=float, default=0.85)
    p.add_argument('--limit', type=int, default=0, help='Limit number of tracks to process (0 = all)')
    args = p.parse_args()

    if args.execute and args.dry_run:
        print('Cannot use --execute and --dry-run together')
        return

    if not os.path.exists(args.csv):
        print('CSV not found:', args.csv)
        return

    # load CSV maps
    external_map: dict[str, Tuple[Optional[float], Optional[float]]] = {}
    title_map: dict[str, Tuple[Optional[float], Optional[float]]] = {}
    title_map_by_artist: dict[str, dict[str, Tuple[Optional[float], Optional[float]]]] = {}
    with open(args.csv, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            dzr = (r.get('dzr_sng_id') or r.get('dzr_id') or r.get('dzr_song_id') or '').strip()
            artist = (r.get('artist_name') or r.get('artist') or '').strip()
            title = (r.get('track_name') or r.get('track') or '').strip()
            val = parse_float(r.get('valence'))
            aro = parse_float(r.get('arousal'))
            if dzr:
                external_map[dzr] = (val, aro)
            if artist and title:
                nartist = normalize(artist)
                ntitle = normalize(title)
                key = nartist + '|' + ntitle
                # prefer entries that have values
                if key not in title_map or (title_map[key][0] is None and val is not None) or (title_map[key][1] is None and aro is not None):
                    title_map[key] = (val, aro)
                    title_map_by_artist.setdefault(nartist, {})[ntitle] = (val, aro)

    session = SessionLocal()
    try:
        q = session.query(Track).filter(or_(Track.valence == None, Track.arousal == None))
        if args.limit and args.limit > 0:
            tracks = q.limit(args.limit).all()
        else:
            tracks = q.all()

        updated = 0
        not_filled = 0
        for t in tracks:
            filled = False
            # try external id
            if t.external_id and t.external_id in external_map:
                val, aro = external_map[t.external_id]
                if val is not None and (t.valence is None or abs((t.valence or 0.0) - val) > 1e-6):
                    if args.execute:
                        t.valence = val
                    filled = True
                if aro is not None and (t.arousal is None or abs((t.arousal or 0.0) - aro) > 1e-6):
                    if args.execute:
                        t.arousal = aro
                    filled = True

            # try title_map exact
            if not filled:
                key = normalize((t.artist.name if t.artist else '') or '') + '|' + normalize(t.title or '')
                if key in title_map:
                    val, aro = title_map[key]
                    if val is not None and (t.valence is None or abs((t.valence or 0.0) - val) > 1e-6):
                        if args.execute:
                            t.valence = val
                        filled = True
                    if aro is not None and (t.arousal is None or abs((t.arousal or 0.0) - aro) > 1e-6):
                        if args.execute:
                            t.arousal = aro
                        filled = True

            # fuzzy fallback (limit candidates to same artist keys)
            if not filled and args.fuzzy:
                nartist = normalize((t.artist.name if t.artist else '') or '')
                candidates = title_map_by_artist.get(nartist, {})
                best_k = None
                best_s = 0.0
                comp = normalize(t.title or '')
                for k in candidates.keys():
                    s = SequenceMatcher(None, comp, k).ratio()
                    if s > best_s:
                        best_s = s
                        best_k = k
                if best_k and best_s >= args.threshold:
                    val, aro = candidates[best_k]
                    if val is not None and (t.valence is None or abs((t.valence or 0.0) - val) > 1e-6):
                        if args.execute:
                            t.valence = val
                        filled = True
                    if aro is not None and (t.arousal is None or abs((t.arousal or 0.0) - aro) > 1e-6):
                        if args.execute:
                            t.arousal = aro
                        filled = True

            if filled:
                updated += 1
                if args.execute:
                    session.add(t)
            else:
                not_filled += 1

        if args.execute:
            session.commit()

        print(f"Done. total_to_process={len(tracks)} updated={updated} not_filled={not_filled}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
