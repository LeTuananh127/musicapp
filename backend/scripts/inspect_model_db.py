import os, json
from pathlib import Path
import sys

print('CWD:', os.getcwd())
model_p = Path('backend/storage/recommender/model.npz')
meta_p = model_p.with_name('model.meta.json')
print('model exists?', model_p.exists())
print('meta exists?', meta_p.exists())
if model_p.exists():
    try:
        import numpy as np
        d = np.load(str(model_p))
        print('npz keys:', list(d.keys()))
        print('user_ids len:', len(d['user_ids']))
        print('track_ids len:', len(d['track_ids']))
        print('user_ids sample:', d['user_ids'][:10])
    except Exception as e:
        print('Could not read npz:', e)
if meta_p.exists():
    try:
        print('meta:', json.load(open(meta_p, 'r', encoding='utf-8')))
    except Exception as e:
        print('Could not read meta:', e)

# DB stats
try:
    # Ensure backend root is on sys.path so we can import the `app` package
    project_root = Path(__file__).resolve().parents[1]
    sys.path.insert(0, str(project_root))
    # Use raw SQL via engine to avoid ORM model attribute issues (missing columns)
    from sqlalchemy import text
    from app.core.db import engine
    with engine.connect() as conn:
        try:
            ucount = conn.execute(text('SELECT COUNT(*) FROM users')).scalar()
        except Exception as e:
            ucount = f'ERR: {e}'
        try:
            icount = conn.execute(text('SELECT COUNT(*) FROM interactions')).scalar()
        except Exception as e:
            icount = f'ERR: {e}'
        try:
            ith_with_track = conn.execute(text("SELECT COUNT(*) FROM interactions WHERE track_id IS NOT NULL")).scalar()
        except Exception as e:
            ith_with_track = f'ERR: {e}'
        try:
            distinct_users = conn.execute(text("SELECT COUNT(DISTINCT user_id) FROM interactions WHERE track_id IS NOT NULL")).scalar()
        except Exception as e:
            distinct_users = f'ERR: {e}'
        try:
            likes = conn.execute(text('SELECT COUNT(*) FROM track_likes')).scalar()
        except Exception as e:
            likes = f'ERR: {e}'

        print('DB: users=', ucount, 'interactions=', icount, 'interactions_with_track=', ith_with_track, 'distinct_users_with_track=', distinct_users, 'tracklikes=', likes)
except Exception as e:
    print('DB check failed:', e)
