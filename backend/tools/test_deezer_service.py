import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from app.services.deezer_service import search_tracks, get_track

def main():
    print('Searching Deezer for "test"...')
    r = search_tracks('test', limit=3)
    print('Found', len(r.get('data', [])))
    for item in r.get('data', []):
        print(item.get('id'), '-', item.get('title'), 'preview:', item.get('preview'))

    if r.get('data'):
        tid = r['data'][0]['id']
        print('\nFetching track', tid)
        t = get_track(tid)
        print('Track title:', t.get('title'))

if __name__ == '__main__':
    main()
