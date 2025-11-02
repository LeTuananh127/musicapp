from app.core.db import SessionLocal
from sqlalchemy import text

s = SessionLocal()
try:
    try:
        s.execute(text("ALTER TABLE artists ADD COLUMN IF NOT EXISTS cover_url VARCHAR(500)"))
        s.commit()
        print('artists.cover_url added (IF NOT EXISTS path)')
    except Exception:
        # fallback for DB that doesn't support IF NOT EXISTS
        try:
            s.execute(text("ALTER TABLE artists ADD COLUMN cover_url VARCHAR(500)"))
            s.commit()
            print('artists.cover_url added (fallback path)')
        except Exception as e:
            s.rollback()
            print('Could not add artists.cover_url:', e)
finally:
    s.close()
