from app.core.db import SessionLocal
from app.models.music import Artist, Track

# Simple development seeding script. Run:  python -m app.dev_seed

def run():
    db = SessionLocal()
    try:
        has = db.query(Track).first()
        if has:
            print("Tracks already exist; skip seeding.")
            return
        artist = Artist(name="Demo Artist")
        db.add(artist)
        db.flush()
        for i in range(1, 21):
            db.add(Track(title=f"Demo Track {i}", artist_id=artist.id, duration_ms=180000))
        db.commit()
        print("Seeded 20 demo tracks.")
    finally:
        db.close()

if __name__ == "__main__":
    run()
