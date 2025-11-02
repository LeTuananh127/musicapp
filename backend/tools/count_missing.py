from app.core.db import SessionLocal
from app.models.music import Track

s = SessionLocal()
try:
    total = s.query(Track).count()
    missing = s.query(Track).filter((Track.valence == None) | (Track.arousal == None)).count()
    both_missing = s.query(Track).filter((Track.valence == None) & (Track.arousal == None)).count()
    print(f"total={total} missing_either={missing} missing_both={both_missing}")
finally:
    s.close()
