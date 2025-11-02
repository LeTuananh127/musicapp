# Test script: insert an interaction and run the same idempotent increment SQL used in router
from datetime import datetime
import os, sys
ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
if ROOT not in sys.path:
    sys.path.insert(0, ROOT)

from app.core.db import SessionLocal
from app.models.music import Interaction, Track
from sqlalchemy import text

session = SessionLocal()
try:
    user_id = 4
    track_id = 21
    # show before
    t = session.query(Track).filter(Track.id == track_id).first()
    print('Before views:', t.id, t.title, t.views)
    # create interaction
    inter = Interaction(user_id=user_id, track_id=track_id, seconds_listened=30, is_completed=True, milestone=100)
    session.add(inter)
    session.commit()
    session.refresh(inter)
    print('Inserted interaction id', inter.id)
    cutoff = datetime.utcnow()
    # run the SQL similar to router logic (but using cutoff 24h earlier)
    from datetime import timedelta
    cutoff = datetime.utcnow() - timedelta(hours=24)
    sql = text(
        "UPDATE tracks SET views = COALESCE(views,0) + 1 WHERE id = :id AND NOT EXISTS ("
        " SELECT 1 FROM interactions i WHERE i.user_id = :uid AND i.track_id = :tid"
        " AND (i.is_completed = 1 OR (i.milestone IS NOT NULL AND i.milestone >= 75))"
        " AND i.id != :iid AND i.played_at >= :cutoff)"
    )
    session.execute(sql, {"id": track_id, "uid": user_id, "tid": track_id, "cutoff": cutoff, "iid": inter.id})
    session.commit()
    t2 = session.query(Track).filter(Track.id == track_id).first()
    print('After views:', t2.id, t2.title, t2.views)
finally:
    session.close()
