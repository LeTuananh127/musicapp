import requests
from typing import Optional

BASE = "https://api.deezer.com"


def search_tracks(q: str, limit: Optional[int] = 10):
    params = {"q": q, "limit": limit}
    resp = requests.get(f"{BASE}/search", params=params, timeout=10)
    resp.raise_for_status()
    return resp.json()


def get_track(track_id: int):
    resp = requests.get(f"{BASE}/track/{track_id}", timeout=10)
    if resp.status_code == 404:
        return None
    resp.raise_for_status()
    return resp.json()
