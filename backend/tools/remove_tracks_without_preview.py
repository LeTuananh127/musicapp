"""
Safe script to remove tracks that have no preview URL.

Usage:
  python remove_tracks_without_preview.py --dry-run
  python remove_tracks_without_preview.py --execute --batch-size 1000

This will list the number of tracks to be removed in dry-run mode. When --execute is provided
the script deletes in batches and commits.
"""
import argparse
import sys
from sqlalchemy import select, delete, func
from app.models.music import Interaction, PlaylistTrack, TrackLike, TrackFeatures

from app.core.db import SessionLocal
from app.models.music import Track


def count_without_preview(session):
    stmt = select(func.count()).select_from(Track).where((Track.preview_url == None) | (Track.preview_url == ""))
    return session.execute(stmt).scalar_one()


def fetch_ids_without_preview(session, limit=None):
    stmt = select(Track.id).where((Track.preview_url == None) | (Track.preview_url == ""))
    if limit:
        stmt = stmt.limit(limit)
    return [r[0] for r in session.execute(stmt).all()]


def filter_unreferenced(session, ids: list[int]) -> list[int]:
    """Return subset of ids that are not referenced in dependent tables."""
    if not ids:
        return []

    referenced = set()

    # interactions
    stmt = select(Interaction.track_id, func.count()).where(Interaction.track_id.in_(ids)).group_by(Interaction.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    # playlist_tracks
    stmt = select(PlaylistTrack.track_id, func.count()).where(PlaylistTrack.track_id.in_(ids)).group_by(PlaylistTrack.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    # track_likes
    stmt = select(TrackLike.track_id, func.count()).where(TrackLike.track_id.in_(ids)).group_by(TrackLike.track_id)
    for tid, cnt in session.execute(stmt).all():
        if tid is not None and cnt > 0:
            referenced.add(tid)

    # track_features (one-to-one)
    stmt = select(TrackFeatures.track_id).where(TrackFeatures.track_id.in_(ids))
    for (tid,) in session.execute(stmt).all():
        if tid is not None:
            referenced.add(tid)

    # return ids that are not referenced
    return [tid for tid in ids if tid not in referenced]


def delete_batch(session, ids):
    if not ids:
        return 0
    stmt = delete(Track).where(Track.id.in_(ids))
    res = session.execute(stmt)
    return res.rowcount


def main():
    parser = argparse.ArgumentParser(description="Remove tracks without preview_url")
    parser.add_argument("--dry-run", action="store_true", help="Only count and show sample ids")
    parser.add_argument("--execute", action="store_true", help="Execute deletion")
    parser.add_argument("--batch-size", type=int, default=500, help="Rows per delete batch")
    parser.add_argument("--sample", type=int, default=10, help="How many sample ids to print in dry-run")
    args = parser.parse_args()

    session = SessionLocal()
    try:
        total = count_without_preview(session)
        print(f"Tracks without preview_url: {total}")

        if args.dry_run or not args.execute:
            samples = fetch_ids_without_preview(session, limit=args.sample)
            print("Sample IDs:")
            for sid in samples:
                print(sid)
            if not args.execute:
                print("Run with --execute to actually delete these tracks in batches.")
                return

        # execute deletion
        deleted = 0
        while True:
            ids = fetch_ids_without_preview(session, limit=args.batch_size)
            if not ids:
                break

            # only delete those ids that have no references
            safe_ids = filter_unreferenced(session, ids)
            if not safe_ids:
                print(f"No unreferenced tracks in this batch (skipping {len(ids)} candidates).")
                # If none in this batch are safe to delete, we should avoid infinite loop.
                # Break to prevent deleting referenced tracks; user must handle referenced ones separately.
                break

            rc = delete_batch(session, safe_ids)
            session.commit()
            deleted += rc
            print(f"Deleted batch of {rc} tracks (unreferenced). Total deleted: {deleted}")

        print(f"Finished. Total deleted: {deleted}")
    finally:
        session.close()


if __name__ == "__main__":
    main()
