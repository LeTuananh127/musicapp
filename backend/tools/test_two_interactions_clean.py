# Test script: delete qualifying interactions in last 24h for a user+track, then insert two interactions
# and verify views increments exactly once.
from datetime import datetime, timedelta
import os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Interaction, Track
from sqlalchemy import or_, and_, text


def run_test(user_id: int, track_id: int):
    session = SessionLocal()
    try:
        t = session.query(Track).filter(Track.id == track_id).first()
        if not t:
            print('Track not found:', track_id)
            return
        print('Initial views:', t.id, t.title, t.views)

        cutoff = datetime.utcnow() - timedelta(hours=24)

        # compute seconds threshold from duration_ms if available
        threshold_seconds = None
        if t.duration_ms:
            try:
                threshold_seconds = int(0.75 * (t.duration_ms or 0) / 1000)
            except Exception:
                threshold_seconds = None

        # Build filter for qualifying interactions in the last 24h
        qual_filters = [Interaction.played_at >= cutoff]
        qual_filters.append(Interaction.user_id == user_id)
        qual_filters.append(Interaction.track_id == track_id)

        qual_condition = (Interaction.is_completed == True) | (Interaction.milestone >= 75)
        if threshold_seconds is not None:
            qual_condition = qual_condition | (Interaction.seconds_listened >= threshold_seconds)

        # Count qualifying interactions
        q = session.query(Interaction).filter(and_(*qual_filters)).filter(qual_condition)
        existing = q.all()
        print('Qualifying interactions in last 24h to delete:', len(existing))

        # Delete them
        deleted = q.delete(synchronize_session=False)
        session.commit()
        print('Deleted qualifying interactions:', deleted)

        # Insert first interaction
        inter1 = Interaction(user_id=user_id, track_id=track_id, seconds_listened=30, is_completed=True, milestone=100)
        session.add(inter1)
        session.commit()
        session.refresh(inter1)
        print('Inserted interaction 1 id', inter1.id)

        # idempotent update SQL copy from router
        sql = text(
            "UPDATE tracks SET views = COALESCE(views,0) + 1 WHERE id = :id AND NOT EXISTS ("
            " SELECT 1 FROM interactions i WHERE i.user_id = :uid AND i.track_id = :tid"
            " AND (i.is_completed = 1 OR (i.milestone IS NOT NULL AND i.milestone >= 75))"
            " AND i.id != :iid AND i.played_at >= :cutoff)"
        )
        session.execute(sql, {"id": track_id, "uid": user_id, "tid": track_id, "cutoff": cutoff, "iid": inter1.id})
        session.commit()
        t2 = session.query(Track).filter(Track.id == track_id).first()
        print('After interaction 1 views:', t2.id, t2.title, t2.views)

        # Insert second interaction
        inter2 = Interaction(user_id=user_id, track_id=track_id, seconds_listened=40, is_completed=True, milestone=100)
        session.add(inter2)
        session.commit()
        session.refresh(inter2)
        print('Inserted interaction 2 id', inter2.id)

        session.execute(sql, {"id": track_id, "uid": user_id, "tid": track_id, "cutoff": cutoff, "iid": inter2.id})
        session.commit()
        t3 = session.query(Track).filter(Track.id == track_id).first()
        print('After interaction 2 views:', t3.id, t3.title, t3.views)

    finally:
        session.close()


if __name__ == '__main__':
    TEST_USER = 4
    TEST_TRACK = 21
    run_test(TEST_USER, TEST_TRACK)
