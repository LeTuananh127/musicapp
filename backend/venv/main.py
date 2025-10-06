from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

app = FastAPI()

# Cho phép gọi từ Flutter (CORS)
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Playlist demo
songs = [
    {
        "id": 1,
        "title": "Song A",
        "artist": "Artist A",
        "url": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3",
        "cover": "https://via.placeholder.com/300.png?text=Cover+A"
    },
    {
        "id": 2,
        "title": "Song B",
        "artist": "Artist B",
        "url": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3",
        "cover": "https://via.placeholder.com/300.png?text=Cover+B"
    },
    {
        "id": 3,
        "title": "Song C",
        "artist": "Artist C",
        "url": "https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3",
        "cover": "https://via.placeholder.com/300.png?text=Cover+C"
    },
]

@app.get("/")
def root():
    return {"message": "Backend running OK"}

@app.get("/songs")
def get_songs():
    return songs
