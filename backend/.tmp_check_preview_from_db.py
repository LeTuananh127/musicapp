from app.core.db import SessionLocal
from app.models.music import Track
import requests

sess = SessionLocal()
try:
    # get a few tracks with non-empty preview
    rows = sess.query(Track).filter(Track.preview_url != None, Track.preview_url != "").limit(10).all()
    if not rows:
        print('No tracks with preview_url found')
    for t in rows:
        print('TRACK', t.id, t.preview_url)
        try:
            headers = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
                'Accept': 'audio/*,*/*',
                'Referer': 'https://www.deezer.com/'
            }
            r = requests.get(t.preview_url, headers=headers, stream=True, timeout=10)
            print('  ->', r.status_code, r.headers.get('content-type'))
            chunk = r.raw.read(512)
            print('  READ-BYTES', len(chunk) if chunk else 0)
            r.close()
        except Exception as e:
            print('  ERR', type(e).__name__, e)
finally:
    sess.close()
