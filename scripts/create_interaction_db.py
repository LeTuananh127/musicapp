from app.core.db import SessionLocal
from app.models.music import Track, Interaction
from sqlalchemy import text
from datetime import datetime

s = SessionLocal()
try:
    tr = s.query(Track).first()
    if not tr:
        print('No track found in DB')
        raise SystemExit(1)
    print('Track id', tr.id, 'views before', tr.views)
    # create interaction
    inter = Interaction(user_id=1, track_id=tr.id, seconds_listened=int((tr.duration_ms or 180000)/1000 * 0.8), is_completed=False, milestone=75)
    s.add(inter)
    s.commit()
    s.refresh(inter)
    print('Inserted interaction id', inter.id)
    # atomic update
    s.execute(text("UPDATE tracks SET views = COALESCE(views,0) + 1 WHERE id = :id"), {'id': int(tr.id)})
    s.commit()
    tr2 = s.query(Track).filter(Track.id == tr.id).first()
    print('Track id', tr.id, 'views after', tr2.views)
finally:
    s.close()
