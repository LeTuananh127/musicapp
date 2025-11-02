import os
import sys
try:
    import requests
    import jwt
except Exception as e:
    print('Missing module:', e)
    sys.exit(1)

base = os.getenv('API_BASE', 'http://127.0.0.1:8000')
# get tracks
r = requests.get(base + '/tracks/')
if r.status_code != 200:
    print('FAILED_GET_TRACKS', r.status_code, r.text)
    sys.exit(1)
tracks = r.json()
if not tracks:
    print('NO_TRACKS')
    sys.exit(1)
track = tracks[0]
track_id = track['id']
print('Using track id', track_id)
# create token for user_id 1 using dev-secret
secret = os.getenv('JWT_SECRET', 'dev-secret')
token = jwt.encode({'sub': '1'}, secret, algorithm='HS256')
print('Token:', token)
# compute seconds_listened as 80% of duration
duration_ms = track.get('duration_ms') or 180000
seconds_listened = int(duration_ms / 1000 * 0.8)
# POST interaction
payload = {'track_id': track_id, 'seconds_listened': seconds_listened, 'milestone':75, 'is_completed': False}
headers = {'Authorization': f'Bearer {token}'}
print('Posting interaction payload', payload)
pr = requests.post(base + '/interactions/', json=payload, headers=headers)
print('POST status', pr.status_code)
print(pr.text)
# fetch track
tr2 = requests.get(base + f'/tracks/{track_id}')
print('Track after fetch status', tr2.status_code)
print(tr2.text)
