import sys
from pathlib import Path
# ensure backend folder is on sys.path so `app` package can be imported when
# running this script from tools/ or repo root
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.deezer_service import search_tracks, get_track
import requests

r=search_tracks('test', limit=1)
print('found', len(r.get('data',[])))
if r.get('data'):
    tid=r['data'][0]['id']
    t=get_track(tid)
    print('id', tid, 'preview', t.get('preview'))
    h=requests.head(t.get('preview'), allow_redirects=True, timeout=10)
    print('head status', h.status_code, 'content-type', h.headers.get('content-type'))
