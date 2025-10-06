"""Data ingestion placeholder for LastFM style interactions.
Usage: python -m app.ingestion.ingest_lastfm --file lastfm.csv
"""
import argparse
import pandas as pd
from sqlalchemy.orm import Session
from sqlalchemy import create_engine
from ..core.config import get_settings
from ..core.db import SessionLocal
from ..models.music import Track, Artist


def ingest(file: str):
    settings = get_settings()
    engine = create_engine(settings.database_url)
    df = pd.read_csv(file)
    # Expect columns: artist_name, track_title, duration_ms
    with Session(engine) as session:
        for _, row in df.iterrows():
            artist = session.query(Artist).filter_by(name=row['artist_name']).first()
            if not artist:
                artist = Artist(name=row['artist_name'])
                session.add(artist)
                session.flush()
            track = Track(title=row['track_title'], artist_id=artist.id, album_id=None, duration_ms=int(row['duration_ms']), preview_url=None, is_explicit=False)
            session.add(track)
        session.commit()
    print("Ingestion complete")

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--file', required=True)
    args = parser.parse_args()
    ingest(args.file)
