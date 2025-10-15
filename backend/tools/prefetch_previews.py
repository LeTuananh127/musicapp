#!/usr/bin/env python3
"""Prefetch Deezer preview mp3 files listed in a CSV.

Usage:
  python tools/prefetch_previews.py --csv preview_candidates_all.csv --sleep 0.2 --limit 0

This reads a CSV with columns: id,title,artist,found_preview_url and downloads the URL into
app/static/audio/deezer/{id}.mp3 if not already present.
"""
import csv
import argparse
from pathlib import Path
import requests
import shutil
import time


def download_preview(track_id: str, url: str, cache_dir: Path, timeout=20, max_retries=2) -> bool:
    target = cache_dir / f"{track_id}.mp3"
    if target.exists():
        print(f"SKIP {track_id} (cached)")
        return True

    headers = {
        'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
        'Accept': 'audio/*,*/*',
        'Referer': 'https://www.deezer.com/'
    }

    tmp = cache_dir / f"{track_id}.tmp"
    for attempt in range(1, max_retries + 1):
        try:
            with requests.get(url, stream=True, timeout=timeout, headers=headers) as r:
                r.raise_for_status()
                with tmp.open('wb') as fh:
                    shutil.copyfileobj(r.raw, fh)
            tmp.replace(target)
            print(f"OK   {track_id}")
            return True
        except requests.exceptions.HTTPError as he:
            status = getattr(he, 'response', None)
            code = status.status_code if status is not None else 'n/a'
            print(f"HTTP {code} for {track_id} attempt {attempt}: {he}")
            # try again; continue loop
        except Exception as e:
            print(f"ERR  {track_id} attempt {attempt}: {e}")
        time.sleep(0.5)

    # cleanup tmp
    try:
        if tmp.exists():
            tmp.unlink()
    except Exception:
        pass
    return False


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--csv', default='preview_candidates_all.csv')
    p.add_argument('--limit', type=int, default=0, help='0=all')
    p.add_argument('--start', type=int, default=0, help='start index (0-based)')
    p.add_argument('--sleep', type=float, default=0.0, help='seconds to sleep between downloads')
    args = p.parse_args()

    csv_path = Path(args.csv)
    if not csv_path.exists():
        print('CSV not found:', csv_path)
        return

    cache_dir = Path(__file__).resolve().parents[2] / 'app' / 'static' / 'audio' / 'deezer'
    cache_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    with csv_path.open(newline='', encoding='utf-8') as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            rows.append(r)

    total = len(rows)
    limit = args.limit if args.limit > 0 else total
    start = args.start

    ok = 0
    fail = 0
    for idx, r in enumerate(rows[start:start+limit]):
        track_id = r.get('id')
        url = r.get('found_preview_url') or r.get('preview_url')
        if not track_id or not url or url.strip().lower() in ('', 'miss'):
            print(f"MISS {track_id} - no url")
            fail += 1
            continue
        print(f"[{idx+start+1}/{total}] Downloading {track_id} ...")
        ok_flag = download_preview(track_id, url, cache_dir)
        if ok_flag:
            ok += 1
        else:
            fail += 1
        if args.sleep:
            time.sleep(args.sleep)

    print(f"Done. ok={ok} fail={fail} total={total}")


if __name__ == '__main__':
    main()
