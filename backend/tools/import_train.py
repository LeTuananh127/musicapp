import os
import csv
from sqlalchemy import func, text
from app.core.db import SessionLocal
from app.models.music import Track, Artist

CSV_PATH = os.path.join(os.path.dirname(__file__), 'train.csv')

def ensure_columns(session):
    # Try to add columns if they do not exist (best-effort)
    try:
        session.execute(text("ALTER TABLE tracks ADD COLUMN IF NOT EXISTS valence DOUBLE"))
        session.execute(text("ALTER TABLE tracks ADD COLUMN IF NOT EXISTS arousal DOUBLE"))
        session.commit()
    except Exception:
        # Some DB versions (older MySQL) don't support IF NOT EXISTS; fallback to try/catch
        try:
            session.execute(text("ALTER TABLE tracks ADD COLUMN valence DOUBLE"))
            session.execute(text("ALTER TABLE tracks ADD COLUMN arousal DOUBLE"))
            session.commit()
        except Exception:
            session.rollback()
            # ignore - columns may already exist or permission issues


def normalize(s: str) -> str:
    return (s or '').strip()


def import_csv(path=CSV_PATH):
    if not os.path.exists(path):
        print('CSV not found at', path)
        return
    session = SessionLocal()
    created = 0
    updated = 0
    skipped = 0
    try:
        ensure_columns(session)
        with open(path, newline='', encoding='utf-8') as fh:
            reader = csv.DictReader(fh)
            for row in reader:
                try:
                    dzr = normalize(row.get('dzr_sng_id') or row.get('dzr_id'))
                    msd_sng = normalize(row.get('MSD_sng_id'))
                    msd_track = normalize(row.get('MSD_track_id'))
                    val = row.get('valence')
                    aro = row.get('arousal')
                    artist_name = normalize(row.get('artist_name') or row.get('artist'))
                    track_name = normalize(row.get('track_name') or row.get('track'))
                    if not track_name:
                        skipped += 1
                        continue
                    try:
                        val_f = float(val) if val not in (None, '') else None
                    except Exception:
                        val_f = None
                    try:
                        aro_f = float(aro) if aro not in (None, '') else None
                    except Exception:
                        aro_f = None

                    # Find existing by title + artist (case-insensitive)
                    q = session.query(Track).join(Artist).filter(func.lower(Track.title) == track_name.lower(), func.lower(Artist.name) == artist_name.lower())
                    existing = q.first()
                    if existing:
                        changed = False
                        if val_f is not None and existing.valence != val_f:
                            existing.valence = val_f
                            changed = True
                        if aro_f is not None and existing.arousal != aro_f:
                            existing.arousal = aro_f
                            changed = True
                        if changed:
                            session.add(existing)
                            updated += 1
                        else:
                            skipped += 1
                        continue

                    # Ensure artist exists (case-insensitive)
                    artist = session.query(Artist).filter(func.lower(Artist.name) == artist_name.lower()).first()
                    if not artist:
                        artist = Artist(name=artist_name)
                        session.add(artist)
                        session.commit()
                        session.refresh(artist)

                    # Create new track with minimal data
                    newt = Track(
                        title=track_name,
                        artist_id=artist.id,
                        album_id=None,
                        duration_ms=0,
                        preview_url=None,
                        cover_url=None,
                        views=0,
                        is_explicit=False,
                        valence=val_f,
                        arousal=aro_f,
                    )
                    session.add(newt)
                    session.commit()
                    created += 1
                except Exception as e:
                    print('Row failed:', e)
                    session.rollback()
                    skipped += 1
    finally:
        session.close()

    print('Done. created=%d updated=%d skipped=%d' % (created, updated, skipped))

if __name__ == '__main__':
    import_csv()
