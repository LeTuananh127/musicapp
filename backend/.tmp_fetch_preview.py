import requests
url = "https://cdnt-preview.dzcdn.net/api/1/1/2/d/8/0/2d806cdb834991f646f97bfc7b89cb24.mp3?hdnea=exp=1759984567~acl=/api/1/1/2/d/8/0/2d806cdb834991f646f97bfc7b89cb24.mp3*~data=user_id=0,application_id=42~hmac=05da16d83fbcd9301d26106ddf06e676c5973825a102487a8eb7882de7f46be1"
headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
    'Accept': 'audio/*,*/*',
    'Referer': 'https://www.deezer.com/'
}
try:
    r = requests.get(url, headers=headers, stream=True, timeout=15)
    print('STATUS', r.status_code)
    print('CONTENT-TYPE', r.headers.get('Content-Type'))
    # read small chunk
    chunk = r.raw.read(2048)
    print('READ-BYTES', len(chunk) if chunk is not None else 0)
    if chunk:
        with open('tmp_preview_head.mp3','wb') as f:
            f.write(chunk)
    r.close()
except Exception as e:
    print('ERR', type(e).__name__, e)
