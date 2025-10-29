"""
Delete tracks listed in a scanner CSV if they are unreferenced.

Usage:
  python delete_tracks_from_csv.py --csv <path> --count 6506 --dry-run
  python delete_tracks_from_csv.py --csv <path> --count 6506 --execute --export-log <path>

This script is conservative: it will only delete tracks that are currently unreferenced
according to the same checks used by `remove_tracks_with_forbidden_preview.py`.
It writes a CSV log of actions performed.
"""
from __future__ import annotations

import argparse
import csv
import os
from typing import List

from app.core.db import SessionLocal
from app.models.music import Track, Interaction, PlaylistTrack, TrackLike, TrackFeatures
from sqlalchemy import select, delete, func


def read_ids_from_scanner(csv_path: str, max_count: int) -> List[int]:
    ids: List[int] = []
    with open(csv_path, newline='', encoding='utf-8') as f:
        r = csv.DictReader(f)
        for row in r:
            action = row.get('action', '').strip()
            if action == 'would-delete-unreferenced':
                try:
                    tid = int(row.get('track_id'))
                except Exception:
                    continue
                ids.append(tid)
                if len(ids) >= max_count:
                    break
    return ids


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


def main():
    parser = argparse.ArgumentParser(description='Delete tracks from scanner CSV if unreferenced')
    parser.add_argument('--csv', required=True, help='Path to scanner CSV')
    parser.add_argument('--count', type=int, required=True, help='How many would-delete-unreferenced ids to process')
    parser.add_argument('--dry-run', action='store_true')
    parser.add_argument('--execute', action='store_true')
    parser.add_argument('--export-log', type=str, default=None, help='CSV path to write action log')
    args = parser.parse_args()

    ids = read_ids_from_scanner(args.csv, args.count)
    print(f"Loaded {len(ids)} candidate ids from {args.csv}")

    session = SessionLocal()
    try:
        safe_to_delete = filter_unreferenced(session, ids)
        print(f"After reference check: {len(safe_to_delete)} ids are still unreferenced and eligible for deletion")

        # Prepare log
        export_path = args.export_log or os.path.join(os.path.dirname(args.csv), 'delete_tracks_log.csv')
        with open(export_path, 'w', newline='', encoding='utf-8') as f:
            w = csv.writer(f)
            w.writerow(['track_id', 'action'])

            for tid in ids:
                if tid in safe_to_delete:
                    if args.execute and not args.dry_run:
                        rc = delete_batch(session, [tid])
                        action = 'deleted' if rc > 0 else 'delete-failed'
                    else:
                        action = 'would-delete'
                else:
                    action = 'referenced-skip'
                w.writerow([tid, action])

            if args.execute and not args.dry_run:
                session.commit()

        print(f"Wrote deletion log to {export_path}")
        print(f"Performed deletions: {'yes' if args.execute and not args.dry_run else 'no (dry-run)'}")
    finally:
        session.close()


if __name__ == '__main__':
    main()
