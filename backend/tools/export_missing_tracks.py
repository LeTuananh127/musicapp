from app.core.db import SessionLocal
from app.models.music import Track
import csv

s = SessionLocal()
try:
    rows = s.query(Track).filter((Track.valence == None) | (Track.arousal == None)).all()
    with open('tools/missing_valence_tracks.csv','w',newline='',encoding='utf-8') as fh:
        w = csv.writer(fh)
        w.writerow(['track_id','title','artist_id','artist_name','external_id','duration_ms'])
        for t in rows:
            artist_name = t.artist.name if t.artist else ''
            w.writerow([t.id,t.title,t.artist_id,artist_name,t.external_id or '',t.duration_ms or 0])
    print('Exported', len(rows), 'rows to tools/missing_valence_tracks.csv')
finally:
    s.close()
