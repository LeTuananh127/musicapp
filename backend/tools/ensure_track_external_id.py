from app.core.db import SessionLocal
from sqlalchemy import text

s = SessionLocal()
try:
    try:
        s.execute(text("ALTER TABLE tracks ADD COLUMN IF NOT EXISTS external_id VARCHAR(255)"))
        s.commit()
        print('tracks.external_id added (IF NOT EXISTS path)')
    except Exception:
        try:
            s.execute(text("ALTER TABLE tracks ADD COLUMN external_id VARCHAR(255)"))
            s.commit()
            print('tracks.external_id added (fallback path)')
        except Exception as e:
            s.rollback()
            print('Could not add tracks.external_id:', e)
finally:
    s.close()
