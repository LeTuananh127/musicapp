"""
Scan all tracks with a preview_url and remove those whose preview URL returns a 4xx (forbidden)
status code. This is intended as a safe, offline tool. It supports dry-run mode and batching.

Usage:
  python remove_tracks_with_forbidden_preview.py --dry-run
  python remove_tracks_with_forbidden_preview.py --execute --batch-size 500 --concurrency 20

Notes:
- The script will only DELETE tracks that are NOT referenced by interactions, playlist_tracks,
  track_likes, or track_features (same safety as remove_tracks_without_preview.py).
- By default it logs results to CSV under ./logs/ (created if missing). In dry-run mode no deletions
  are performed; in execute mode only unreferenced tracks are deleted.
- This tool uses `requests` with a small thread pool to test preview URLs. It sends a HEAD request
  and falls back to a Range GET if HEAD is not allowed.
"""
from __future__ import annotations

import argparse
import csv
import os
import sys
import time
from datetime import datetime
from typing import List, Tuple
from concurrent.futures import ThreadPoolExecutor, as_completed

import requests
from sqlalchemy import select, delete, func

from app.core.db import SessionLocal
from app.models.music import Track, Interaction, PlaylistTrack, TrackLike, TrackFeatures


def fetch_batch(session, min_id: int = 0, limit: int = 500) -> List[Tuple[int, str]]:
    stmt = select(Track.id, Track.preview_url).where((Track.preview_url != None) & (Track.preview_url != ""))
    stmt = stmt.where(Track.id > min_id).order_by(Track.id).limit(limit)
    return [(r[0], r[1]) for r in session.execute(stmt).all()]


def filter_unreferenced(session, ids: List[int]) -> List[int]:
    if not ids:
        return []

    referenced = set()

    stmt = select(Interaction.track_id, func.count()).where(Interaction.track_id.in_(ids)).group_by(Interaction.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    stmt = select(PlaylistTrack.track_id, func.count()).where(PlaylistTrack.track_id.in_(ids)).group_by(PlaylistTrack.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    stmt = select(TrackLike.track_id, func.count()).where(TrackLike.track_id.in_(ids)).group_by(TrackLike.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    stmt = select(TrackFeatures.track_id).where(TrackFeatures.track_id.in_(ids))
    for (tid,) in session.execute(stmt).all():
        if tid is not None:
            referenced.add(tid)

    return [tid for tid in ids if tid not in referenced]


def delete_batch(session, ids: List[int]) -> int:
    if not ids:
        return 0
    stmt = delete(Track).where(Track.id.in_(ids))
    res = session.execute(stmt)
    return res.rowcount


def check_preview_url(session: requests.Session, url: str, timeout: float = 6.0) -> Tuple[int, str]:
    """Return (status_code, note). status_code is the HTTP status if available or -1 on network error.
    note contains a short explanation (e.g., 'head', 'range-get', 'error').
    """
    headers = {"User-Agent": "musicapp-preview-check/1.0"}
    try:
        # Try HEAD first
        r = session.head(url, timeout=timeout, allow_redirects=True, headers=headers)
        code = r.status_code
        # Some servers return 405 for HEAD; if 4xx on HEAD, try a tiny GET with Range fallback
        if code >= 400:
            # fallback to byte range GET
            r2 = session.get(url, timeout=timeout, headers={**headers, "Range": "bytes=0-1"}, stream=True)
            return r2.status_code, "range-get"
        return code, "head"
    except requests.RequestException as exc:
        # Try one GET attempt as last resort
        try:
            r = session.get(url, timeout=timeout, headers={**headers, "Range": "bytes=0-1"}, stream=True)
            return r.status_code, "range-get-exc-fallback"
        except requests.RequestException:
            return -1, f"error:{str(exc)[:200]}"


def ensure_logs_dir() -> str:
    logs_dir = os.path.join(os.path.dirname(__file__), "logs")
    os.makedirs(logs_dir, exist_ok=True)
    return logs_dir


def main():
    parser = argparse.ArgumentParser(description="Remove tracks whose preview URL returns 4xx/403.")
    parser.add_argument("--dry-run", action="store_true", help="Only report; do not delete anything")
    parser.add_argument("--execute", action="store_true", help="Actually delete unreferenced tracks that are forbidden")
    parser.add_argument("--batch-size", type=int, default=500, help="How many tracks to scan per DB batch")
    parser.add_argument("--concurrency", type=int, default=20, help="Concurrent HTTP checks")
    parser.add_argument("--timeout", type=float, default=6.0, help="HTTP timeout seconds per request")
    args = parser.parse_args()

    session_db = SessionLocal()
    logs_dir = ensure_logs_dir()
    ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
    csv_path = os.path.join(logs_dir, f"forbidden_preview_scan_{ts}.csv")

    total_found = 0
    total_deleted = 0
    processed = 0

    requests_session = requests.Session()
    adapter = requests.adapters.HTTPAdapter(pool_maxsize=args.concurrency)
    requests_session.mount("http://", adapter)
    requests_session.mount("https://", adapter)

    with open(csv_path, "w", newline='', encoding='utf-8') as csvfile:
        writer = csv.writer(csvfile)
        writer.writerow(["track_id", "preview_url", "status_code", "note", "action"])

        min_id = 0
        while True:
            batch = fetch_batch(session_db, min_id=min_id, limit=args.batch_size)
            if not batch:
                break

            ids_in_batch = [tid for tid, _ in batch]
            processed += len(batch)
            min_id = max(ids_in_batch)

            # check URLs concurrently
            results = {}
            with ThreadPoolExecutor(max_workers=args.concurrency) as exe:
                futures = {exe.submit(check_preview_url, requests_session, url, args.timeout): (tid, url) for tid, url in batch}
                for fut in as_completed(futures):
                    tid, url = futures[fut]
                    try:
                        status_code, note = fut.result()
                    except Exception as exc:
                        status_code, note = -1, f"error:{str(exc)[:200]}"
                    results[tid] = (url, status_code, note)

            # collect forbidden (4xx) codes
            forbidden_ids = [tid for tid, (url, status, note) in results.items() if 400 <= status < 500]
            total_found += len(forbidden_ids)

            if not forbidden_ids:
                # write non-forbidden rows for visibility
                for tid, (url, status, note) in results.items():
                    writer.writerow([tid, url, status, note, "keep"])
                session_db.commit()
                continue

            # filter unreferenced
            safe_to_delete = filter_unreferenced(session_db, forbidden_ids)

            # write entries and optionally delete
            for tid in forbidden_ids:
                url, status, note = results[tid]
                action = "found-forbidden"
                if tid in safe_to_delete and args.execute:
                    rc = delete_batch(session_db, [tid])
                    if rc > 0:
                        action = "deleted"
                        total_deleted += rc
                    else:
                        action = "delete-failed"
                elif tid in safe_to_delete:
                    action = "would-delete-unreferenced"
                else:
                    action = "referenced-skip"

                writer.writerow([tid, url, status, note, action])

            # commit deletions if any
            if args.execute and safe_to_delete:
                session_db.commit()

            # flush to disk
            csvfile.flush()

            # small sleep to avoid hammering DB or remote hosts
            time.sleep(0.1)

        print(f"Processed {processed} tracks; forbidden found: {total_found}; deleted: {total_deleted}")
        print(f"CSV log written to: {csv_path}")

    session_db.close()


if __name__ == "__main__":
    main()
