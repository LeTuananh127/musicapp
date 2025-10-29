"""
Attempt to fill missing preview_url for tracks by searching Deezer API.

Usage:
  python fill_preview_from_deezer.py --dry-run --limit 100
  python fill_preview_from_deezer.py --execute --limit 100 --batch-size 50

This is best-effort and uses simple title+artist searches; results should be reviewed.
"""
import argparse
import time
import csv
from typing import Optional
from urllib.parse import quote_plus

import requests
from requests.exceptions import RequestException

from app.core.db import SessionLocal
from app.models.music import Track, Artist

DEEZER_SEARCH = "https://api.deezer.com/search"


def find_preview_for_track(title: str, artist_name: Optional[str], timeout: float = 10.0, max_retries: int = 3, backoff_factor: float = 0.5) -> Optional[str]:
    """
    Query Deezer for a preview URL using title (+ artist_name if available).

    This function will retry on transient network errors using exponential backoff.
    Returns the preview URL string if found, otherwise None.
    """
    q = title
    if artist_name:
        q = f"{title} {artist_name}"
    params = {"q": q, "limit": 5}

    for attempt in range(1, max_retries + 1):
        try:
            r = requests.get(DEEZER_SEARCH, params=params, timeout=timeout)
            if r.status_code != 200:
                # Treat non-200 as not found for our purposes
                return None
            data = r.json()
            for item in data.get("data", []):
                preview = item.get("preview")
                if preview:
                    return preview
            return None
        except RequestException as exc:
            # On last attempt, give up and return None; otherwise backoff and retry
            if attempt == max_retries:
                print(f"deezer request failed after {max_retries} attempts: {exc}")
                return None
            backoff = backoff_factor * (2 ** (attempt - 1))
            print(f"deezer request error (attempt {attempt}/{max_retries}): {exc} — retrying in {backoff:.2f}s")
            time.sleep(backoff)
    return None


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--execute", action="store_true")
    parser.add_argument("--limit", type=int, default=200, help="How many tracks to scan")
    parser.add_argument("--batch-size", type=int, default=50, help="Commit every N updates")
    parser.add_argument("--export-csv", type=str, default=None, help="If provided, write CSV of found previews")
    parser.add_argument("--refresh-existing", action="store_true", help="Also attempt to refresh preview_url for tracks that already have one")
    parser.add_argument("--ids", type=str, default=None, help="Optional comma-separated list of track ids to process (overrides limit)")
    parser.add_argument("--timeout", type=float, default=10.0, help="HTTP request timeout (seconds)")
    parser.add_argument("--max-retries", type=int, default=3, help="Max retries for Deezer requests on failure")
    parser.add_argument("--backoff-factor", type=float, default=0.5, help="Backoff factor (seconds) used for exponential backoff")
    args = parser.parse_args()

    session = SessionLocal()
    try:
        if args.ids:
            ids = [int(x.strip()) for x in args.ids.split(',') if x.strip()]
            to_scan = session.query(Track).filter(Track.id.in_(ids)).all()
        else:
            if args.refresh_existing:
                stmt = session.query(Track).limit(args.limit)
            else:
                stmt = session.query(Track).filter((Track.preview_url == None) | (Track.preview_url == "")).limit(args.limit)
            to_scan = stmt.all()

        print(f"Scanning {len(to_scan)} tracks (dry_run={args.dry_run}, refresh_existing={args.refresh_existing})")

        updated = 0
        candidates = []
        for i, t in enumerate(to_scan, start=1):
            artist_name = None
            if t.artist_id:
                a = session.get(Artist, t.artist_id)
                if a:
                    artist_name = a.name

            preview = find_preview_for_track(t.title, artist_name, timeout=args.timeout, max_retries=args.max_retries, backoff_factor=args.backoff_factor)
            print(f"{i}/{len(to_scan)} id={t.id} -> preview={'FOUND' if preview else 'miss'}")
            if preview and args.execute:
                t.preview_url = preview
                session.add(t)
                updated += 1
                if updated % args.batch_size == 0:
                    session.commit()
            if preview:
                # record candidate (dry-run or execute)
                candidates.append((t.id, t.title, artist_name or "", preview))
            time.sleep(0.25)  # rate-limit

        if args.execute:
            session.commit()
            print(f"Updated {updated} tracks")
        if args.export_csv:
            # write CSV of candidates
            path = args.export_csv
            with open(path, "w", newline='', encoding='utf-8') as f:
                w = csv.writer(f)
                w.writerow(["id", "title", "artist", "found_preview_url"])
                for row in candidates:
                    w.writerow(row)
            print(f"Wrote {len(candidates)} candidate rows to {path}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
