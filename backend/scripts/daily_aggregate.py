"""Run daily aggregation of interactions into UserPreferredArtist.

This script is intended to be scheduled (Windows Task Scheduler / cron) and will
compute top-N artists per user over the past `days` days and store them in the
`user_preferred_artists` table.

Usage:
    python daily_aggregate.py --days 30 --top-n 10

Ensure the project's virtualenv is activated or the appropriate Python is used
when scheduling the task.
"""
from datetime import datetime, timedelta
from collections import defaultdict
import argparse

from app.core.db import SessionLocal
from app.models.music import Interaction, UserPreferredArtist
from sqlalchemy import func, desc


def aggregate_all(days: int = 30, top_n: int = 10):
    cutoff = datetime.utcnow() - timedelta(days=days)
    db = SessionLocal()
    try:
        rows = (
            db.query(Interaction.user_id, Interaction.artist_id, func.sum(Interaction.seconds_listened).label('total_seconds'))
            .filter(Interaction.user_id != None)
            .filter(Interaction.played_at >= cutoff)
            .group_by(Interaction.user_id, Interaction.artist_id)
            .order_by(Interaction.user_id, desc('total_seconds'))
            .all()
        )

        per_user = defaultdict(list)
        for user_id, artist_id, total in rows:
            per_user[user_id].append((artist_id, total))

        updated = 0
        for uid, lst in per_user.items():
            lst_sorted = sorted(lst, key=lambda x: x[1], reverse=True)[:top_n]
            db.query(UserPreferredArtist).filter(UserPreferredArtist.user_id == uid).delete()
            for aid, _ in lst_sorted:
                if not aid:
                    continue
                db.add(UserPreferredArtist(user_id=uid, artist_id=aid))
            updated += 1
        db.commit()
        return updated
    finally:
        db.close()


def main():
    p = argparse.ArgumentParser()
    p.add_argument('--days', type=int, default=30)
    p.add_argument('--top-n', type=int, default=10)
    args = p.parse_args()
    updated = aggregate_all(days=args.days, top_n=args.top_n)
    print(f"Updated preferred artists for {updated} users")


if __name__ == '__main__':
    main()
