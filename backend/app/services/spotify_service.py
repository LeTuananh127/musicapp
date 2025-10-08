import base64
import time
from typing import Any, Dict, List, Optional

import requests
from ..core.config import get_settings

TOKEN_URL = "https://accounts.spotify.com/api/token"
API_BASE = "https://api.spotify.com/v1"

_cached_token: Optional[str] = None
_token_expiry: float = 0.0

class SpotifyAuthError(Exception):
    pass

def _get_client_credentials() -> tuple[str, str]:
    settings = get_settings()
    if not settings.spotify_client_id or not settings.spotify_client_secret:
        raise SpotifyAuthError("Spotify credentials not configured (SPOTIFY_CLIENT_ID / SPOTIFY_CLIENT_SECRET)")
    return settings.spotify_client_id, settings.spotify_client_secret

def get_app_token() -> str:
    global _cached_token, _token_expiry
    now = time.time()
    if _cached_token and now < _token_expiry - 30:  # reuse if not close to expiry
        return _cached_token

    client_id, client_secret = _get_client_credentials()
    basic = base64.b64encode(f"{client_id}:{client_secret}".encode()).decode()
    headers = {"Authorization": f"Basic {basic}", "Content-Type": "application/x-www-form-urlencoded"}
    data = {"grant_type": "client_credentials"}
    resp = requests.post(TOKEN_URL, headers=headers, data=data, timeout=10)
    if resp.status_code != 200:
        raise SpotifyAuthError(f"Failed to obtain token: {resp.status_code} {resp.text}")
    js = resp.json()
    _cached_token = js.get("access_token")
    _token_expiry = now + int(js.get("expires_in", 3600))
    return _cached_token  # type: ignore

def _auth_header() -> Dict[str, str]:
    token = get_app_token()
    return {"Authorization": f"Bearer {token}"}

def search_tracks(query: str, limit: int = 10) -> List[Dict[str, Any]]:
    params = {"q": query, "type": "track", "limit": limit}
    resp = requests.get(f"{API_BASE}/search", headers=_auth_header(), params=params, timeout=10)
    if resp.status_code != 200:
        raise RuntimeError(f"Spotify search failed: {resp.status_code} {resp.text}")
    js = resp.json()
    items = js.get("tracks", {}).get("items", [])
    out: List[Dict[str, Any]] = []
    for it in items:
        out.append({
            "id": it.get("id"),
            "name": it.get("name"),
            "artists": [a.get("name") for a in it.get("artists", [])],
            "album": it.get("album", {}).get("name"),
            "duration_ms": it.get("duration_ms"),
            "preview_url": it.get("preview_url"),
            "external_url": it.get("external_urls", {}).get("spotify"),
        })
    return out

def get_track(track_id: str) -> Dict[str, Any]:
    resp = requests.get(f"{API_BASE}/tracks/{track_id}", headers=_auth_header(), timeout=10)
    if resp.status_code == 404:
        raise KeyError("Track not found")
    if resp.status_code != 200:
        raise RuntimeError(f"Spotify get track failed: {resp.status_code} {resp.text}")
    it = resp.json()
    return {
        "id": it.get("id"),
        "name": it.get("name"),
        "artists": [a.get("name") for a in it.get("artists", [])],
        "album": it.get("album", {}).get("name"),
        "duration_ms": it.get("duration_ms"),
        "preview_url": it.get("preview_url"),
        "external_url": it.get("external_urls", {}).get("spotify"),
    }
