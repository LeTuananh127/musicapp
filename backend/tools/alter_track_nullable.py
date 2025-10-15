from app.core.db import engine
from sqlalchemy import text

with engine.connect() as conn:
    print('Altering interactions.track_id to allow NULL...')
    conn.execute(text('ALTER TABLE interactions MODIFY COLUMN track_id INT NULL'))
    conn.commit()
    print('Done')
