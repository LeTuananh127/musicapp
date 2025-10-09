from sqlalchemy import text
from app.core.db import engine

def ensure_column():
    with engine.connect() as conn:
        # Check information_schema for existing column (MySQL)
        try:
            res = conn.execute(text("""
                SELECT COUNT(*) as c FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = 'interactions' AND COLUMN_NAME = 'external_track_id'
            """))
            row = res.first()
            if row is not None and int(row[0]) > 0:
                print('Column external_track_id already exists')
                return
        except Exception as e:
            print('Could not query information_schema:', e)
        try:
            print('Adding column external_track_id to interactions...')
            conn.execute(text("ALTER TABLE interactions ADD COLUMN external_track_id VARCHAR(255) NULL"))
            print('Column added.')
        except Exception as e:
            print('Failed to add column:', e)

if __name__ == '__main__':
    ensure_column()
