# Test script: ensure view increments only when seconds_listened >= 75% (or is_completed)
from datetime import datetime, timedelta
import os, sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Interaction, Track
from sqlalchemy import text


def run_test(user_id: int, track_id: int):
    session = SessionLocal()
    try:
        t = session.query(Track).filter(Track.id == track_id).first()
        print('Track:', t.id, t.title, 'duration_ms=', t.duration_ms, 'views=', t.views)

        # delete qualifying interactions in last 24h
        cutoff = datetime.utcnow() - timedelta(hours=24)
        # determine threshold seconds
        th = None
        if t.duration_ms:
            th = int(0.75 * (t.duration_ms or 0) / 1000)
        # delete any qualifying interactions
        from sqlalchemy import and_
        from app.models.music import Interaction
        if th is not None:
            q = session.query(Interaction).filter(Interaction.user_id == user_id, Interaction.track_id == track_id, Interaction.played_at >= cutoff).filter((Interaction.is_completed == True) | (Interaction.seconds_listened >= th))
        else:
            q = session.query(Interaction).filter(Interaction.user_id == user_id, Interaction.track_id == track_id, Interaction.played_at >= cutoff, Interaction.is_completed == True)
        deleted = q.delete(synchronize_session=False)
        session.commit()
        print('Deleted qualifying interactions:', deleted)

        before = session.query(Track).filter(Track.id == track_id).first()
        print('Views before:', before.views)

        # insert interaction below threshold
        low_seconds = max(1, (th - 1) if th else 10)
        inter_low = Interaction(user_id=user_id, track_id=track_id, seconds_listened=low_seconds, is_completed=False)
        session.add(inter_low)
        session.commit()
        session.refresh(inter_low)
        print('Inserted low interaction id', inter_low.id, 'seconds_listened=', low_seconds)
        # run same SQL used by router
        sql = text(
            "UPDATE tracks SET views = COALESCE(views,0) + 1 WHERE id = :id AND NOT EXISTS ("
            " SELECT 1 FROM interactions i WHERE i.user_id = :uid AND i.track_id = :tid"
            " AND (i.is_completed = 1 OR (i.seconds_listened >= :th))"
            " AND i.id != :iid AND i.played_at >= :cutoff)"
        )
        session.execute(sql, {"id": track_id, "uid": user_id, "tid": track_id, "th": th or 0, "cutoff": cutoff, "iid": inter_low.id})
        session.commit()
        after_low = session.query(Track).filter(Track.id == track_id).first()
        print('Views after low interaction:', after_low.views)

        # insert interaction at/above threshold
        high_seconds = th if th else 100
        inter_high = Interaction(user_id=user_id, track_id=track_id, seconds_listened=high_seconds, is_completed=False)
        session.add(inter_high)
        session.commit()
        session.refresh(inter_high)
        print('Inserted high interaction id', inter_high.id, 'seconds_listened=', high_seconds)
        session.execute(sql, {"id": track_id, "uid": user_id, "tid": track_id, "th": th or 0, "cutoff": cutoff, "iid": inter_high.id})
        session.commit()
        after_high = session.query(Track).filter(Track.id == track_id).first()
        print('Views after high interaction:', after_high.views)

    finally:
        session.close()


if __name__ == '__main__':
    run_test(4, 21)
