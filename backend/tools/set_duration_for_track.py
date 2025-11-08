"""
Usage:
  python tools/set_duration_for_track.py <track_id>

Finds the downloaded audio file for the given track id under app/static/audio/,
reads its duration with mutagen and updates Track.duration_ms in the DB.
"""
import sys
import os
from mutagen import File as MutagenFile

from app.core.db import SessionLocal
from app.models.music import Track


def find_audio(track_id: int) -> str | None:
    audio_dir = os.path.join('app', 'static', 'audio')
    if not os.path.isdir(audio_dir):
        return None
    for fname in os.listdir(audio_dir):
        if fname.startswith(str(track_id)):
            return os.path.join(audio_dir, fname)
    return None


if __name__ == '__main__':
    if len(sys.argv) < 2:
        print('Usage: python tools/set_duration_for_track.py <track_id>')
        sys.exit(1)
    try:
        track_id = int(sys.argv[1])
    except Exception:
        print('Invalid track id')
        sys.exit(1)

    path = find_audio(track_id)
    if not path:
        print('No audio file found for track', track_id)
        sys.exit(1)

    try:
        m = MutagenFile(path)
        if not m or not getattr(m, 'info', None) or getattr(m.info, 'length', None) is None:
            print('Mutagen could not read duration for', path)
            sys.exit(1)
        dur_ms = int(m.info.length * 1000)
    except Exception as e:
        print('Error reading file with mutagen:', e)
        sys.exit(1)

    db = SessionLocal()
    try:
        tr = db.query(Track).filter(Track.id == track_id).first()
        if not tr:
            print('Track not found in DB:', track_id)
            sys.exit(1)
        tr.duration_ms = dur_ms
        db.add(tr)
        db.commit()
        print('Updated track', track_id, 'duration_ms =', dur_ms)
    finally:
        db.close()
