"""Compare DB-exported preview/cover URLs with source CSV (import_train_output.csv).

Outputs: tools/preview_mismatch_report.csv with columns:
  match_key,match_type,track_id,db_preview,src_preview,db_cover,src_cover,note

Usage:
  python tools/compare_db_with_csv_previews.py --db_export tools/db_tracks_preview_export.csv --src_csv tools/import_train_output.csv
"""
from __future__ import annotations
import csv
import os
import sys
import unicodedata
import string
from difflib import SequenceMatcher

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)


def normalize(s: str) -> str:
    if not s:
        return ''
    s = s.strip().lower()
    s = unicodedata.normalize('NFD', s)
    s = ''.join(ch for ch in s if unicodedata.category(ch) != 'Mn')
    s = ''.join(ch for ch in s if ch not in string.punctuation)
    return s


def load_db_export(path):
    out = {}
    with open(path, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            track_id = r.get('id')
            artist = r.get('artist_name') or ''
            title = r.get('title') or ''
            external = r.get('external_id') or ''
            preview = r.get('preview_url') or ''
            cover = r.get('cover_url') or ''
            key_ext = external.strip()
            key_norm = normalize(artist) + '|' + normalize(title)
            out.setdefault('by_ext', {})[key_ext] = {'id': track_id, 'preview': preview, 'cover': cover, 'artist': artist, 'title': title}
            out.setdefault('by_norm', {})[key_norm] = {'id': track_id, 'preview': preview, 'cover': cover, 'artist': artist, 'title': title}
    return out


def load_src_csv(path):
    rows = []
    with open(path, newline='', encoding='utf-8') as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            dzr = (r.get('dzr') or r.get('dzr_sng_id') or '').strip()
            artist = (r.get('artist') or r.get('artist_name') or '').strip()
            title = (r.get('title') or r.get('track') or r.get('track_name') or '').strip()
            preview = (r.get('preview') or '').strip()
            cover = (r.get('cover') or '').strip()
            rows.append({'dzr': dzr, 'artist': artist, 'title': title, 'preview': preview, 'cover': cover})
    return rows


def main():
    import argparse
    p = argparse.ArgumentParser()
    p.add_argument('--db_export', default='tools/db_tracks_preview_export.csv')
    p.add_argument('--src_csv', default='tools/import_train_output.csv')
    p.add_argument('--out', default='tools/preview_mismatch_report.csv')
    args = p.parse_args()

    if not os.path.exists(args.db_export):
        print('DB export not found:', args.db_export); return
    if not os.path.exists(args.src_csv):
        print('Source CSV not found:', args.src_csv); return

    db = load_db_export(args.db_export)
    src = load_src_csv(args.src_csv)

    mismatches = []
    matched = 0
    not_found = 0

    for r in src:
        if not r['preview'] and not r['cover']:
            continue
        found = None
        match_type = None
        if r['dzr'] and r['dzr'] in db['by_ext']:
            found = db['by_ext'][r['dzr']]
            match_type = 'dzr'
        else:
            key_norm = normalize(r['artist']) + '|' + normalize(r['title'])
            if key_norm in db['by_norm']:
                found = db['by_norm'][key_norm]
                match_type = 'norm'

        if not found:
            not_found += 1
            mismatches.append((key_norm, 'not_found', '', '', '', r['preview'], r['cover'], 'not_found'))
            continue

        matched += 1
        db_prev = (found.get('preview') or '').strip()
        src_prev = (r.get('preview') or '').strip()
        db_cov = (found.get('cover') or '').strip()
        src_cov = (r.get('cover') or '').strip()
        note = ''
        if db_prev != src_prev:
            note += 'preview_mismatch;'
        if db_cov != src_cov:
            note += 'cover_mismatch;'
        if note:
            mismatches.append((f"{found.get('id')}", match_type, found.get('id'), db_prev, src_prev, db_cov, src_cov, note))

    # write report
    with open(args.out, 'w', newline='', encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['match_key','match_type','track_id','db_preview','src_preview','db_cover','src_cover','note'])
        for row in mismatches:
            w.writerow(row)

    print('Done. matched_with_preview=', matched, 'mismatches=', len(mismatches), 'not_found=', not_found)
    print('Report written to', args.out)


if __name__ == '__main__':
    main()
