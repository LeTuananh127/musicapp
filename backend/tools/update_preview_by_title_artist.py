"""Update Track.preview_url (and optionally cover_url) by matching CSV rows to DB tracks

Reads a CSV (default: tools/import_train_output.csv) with columns: dzr,artist,title,preview,cover
and for each row attempts to find a Track by normalized artist+title. If a match is found and the
CSV contains a non-empty preview URL, the script will (dry-run by default) report the change or
update the DB when --execute is provided.

Usage:
  python tools/update_preview_by_title_artist.py [--csv PATH] [--dry-run] [--execute] [--fuzzy] [--threshold 0.85] [--limit N]
"""
from __future__ import annotations
import csv
import os
import sys
import argparse
import unicodedata
import string
from difflib import SequenceMatcher

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Track, Artist
from sqlalchemy import func


def normalize(s: str) -> str:
    if not s:
        return ''
    s = s.strip().lower()
    s = unicodedata.normalize('NFD', s)
    s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
    s = ''.join(ch for ch in s if ch not in string.punctuation)
    return s


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='tools/import_train_output.csv')
    p.add_argument('--dry-run', action='store_true')
    p.add_argument('--execute', action='store_true')
    p.add_argument('--fuzzy', action='store_true')
    p.add_argument('--threshold', type=float, default=0.85)
    p.add_argument('--limit', type=int, default=0)
    return p.parse_args()


def best_fuzzy_match(name: str, candidates: dict[str, int]) -> tuple[str | None, float]:
    best = None
    best_score = 0.0
    for cand in candidates.keys():
        s = SequenceMatcher(None, name, cand).ratio()
        if s > best_score:
            best_score = s
            best = cand
    return best, best_score


def main():
    args = parse_args()
    if args.execute and args.dry_run:
        print('Cannot use --execute and --dry-run together')
        return

    if not os.path.exists(args.csv):
        print('CSV not found:', args.csv)
        return

    # load CSV rows
    rows = []
    with open(args.csv, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            rows.append(r)
            if args.limit and len(rows) >= args.limit:
                break

    session = SessionLocal()
    try:
        # preload tracks mapped by normalized artist|title
        db_tracks = session.query(Track).all()
        title_map = {}
        title_map_by_artist = {}
        for t in db_tracks:
            nartist = normalize((t.artist.name if t.artist else '') or '')
            ntitle = normalize(t.title or '')
            key = nartist + '|' + ntitle
            title_map.setdefault(key, []).append(t)
            title_map_by_artist.setdefault(nartist, {})[ntitle] = t

        updates = []
        skipped = 0
        not_found = 0
        for r in rows:
            dzr = (r.get('dzr') or '').strip()
            artist = (r.get('artist') or '').strip()
            title = (r.get('title') or '').strip()
            preview = (r.get('preview') or '').strip()
            cover = (r.get('cover') or '').strip()
            if not preview:
                skipped += 1
                continue
            nartist = normalize(artist)
            ntitle = normalize(title)
            key = nartist + '|' + ntitle
            found = None
            if key in title_map_by_artist.get(nartist, {}):
                found = title_map_by_artist[nartist][ntitle]
            elif key in title_map:
                # fallback, take first
                found = title_map[key][0]
            elif args.fuzzy:
                # fuzzy restricted to same artist
                candidates = title_map_by_artist.get(nartist, {})
                if candidates:
                    best_k, score = best_fuzzy_match(ntitle, candidates)
                    if best_k and score >= args.threshold:
                        found = candidates[best_k]
                else:
                    # global fuzzy
                    best_k, score = best_fuzzy_match(ntitle, {k.split('|',1)[1]:1 for k in title_map.keys()})
                    if best_k and score >= args.threshold:
                        # find first matching key
                        for k in title_map.keys():
                            if k.endswith('|' + best_k):
                                found = title_map[k][0]
                                break

            if not found:
                not_found += 1
                continue

            updates.append((found.id, found.title, found.artist.name if found.artist else None, preview, cover))
            if args.execute:
                try:
                    t = session.query(Track).filter(Track.id == found.id).first()
                    if t:
                        t.preview_url = preview or t.preview_url
                        if cover:
                            t.cover_url = cover or t.cover_url
                        session.add(t)
                except Exception:
                    pass

        if args.execute:
            session.commit()

        print(f"Rows processed={len(rows)} preview_updates={len(updates)} skipped_no_preview={skipped} not_found={not_found}")
        if updates:
            print('Sample updates (id, title, artist, preview, cover):')
            for u in updates[:10]:
                print(u)
    finally:
        session.close()


if __name__ == '__main__':
    main()
