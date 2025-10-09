from fastapi import APIRouter, HTTPException
from fastapi.responses import StreamingResponse
from typing import Optional
import requests
from ..services.deezer_service import search_tracks, get_track
from pathlib import Path
import shutil

router = APIRouter(prefix="/deezer", tags=["deezer"])


@router.get('/search')
async def deezer_search(q: str, limit: Optional[int] = 10):
    """Search Deezer tracks by query string."""
    try:
        res = search_tracks(q, limit=limit)
        return res
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/track/{track_id}')
async def deezer_track(track_id: int):
    """Get Deezer track info (includes preview URL)."""
    try:
        t = get_track(track_id)
        if not t:
            raise HTTPException(status_code=404, detail='Track not found')
        return t
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@router.get('/stream/{track_id}')
async def deezer_stream(track_id: int):
    """Proxy Deezer track preview as a streaming response.

    This avoids CORS or referrer-based blocking on the client by serving the
    preview MP3 through our backend. Only previews (30s mp3) are proxied.
    """
    try:
        t = get_track(track_id)
        if not t or not t.get('preview'):
            raise HTTPException(status_code=404, detail='Preview not available')

        preview_url = t.get('preview')
        # Local cache path
        cache_dir = Path(__file__).resolve().parents[2] / 'app' / 'static' / 'audio' / 'deezer'
        cache_dir.mkdir(parents=True, exist_ok=True)
        cached_file = cache_dir / f'{track_id}.mp3'

        if not cached_file.exists():
            # Download preview into cache
            try:
                with requests.get(preview_url, stream=True, timeout=10) as resp:
                    resp.raise_for_status()
                    # Write to a temp file then atomically move
                    tmp = cache_dir / f'{track_id}.tmp'
                    with tmp.open('wb') as fh:
                        shutil.copyfileobj(resp.raw, fh)
                    tmp.replace(cached_file)
            except Exception as e:
                # If caching fails, fall back to proxy streaming directly
                resp = requests.get(preview_url, stream=True, timeout=10)
                resp.raise_for_status()
                headers = {}
                if 'content-length' in resp.headers:
                    headers['Content-Length'] = resp.headers['content-length']
                content_type = resp.headers.get('content-type', 'audio/mpeg')
                return StreamingResponse(resp.iter_content(chunk_size=1024), media_type=content_type, headers=headers)

        # Serve cached file (stream from disk)
        f = cached_file.open('rb')
        def file_iter():
            try:
                while True:
                    chunk = f.read(1024)
                    if not chunk:
                        break
                    yield chunk
            finally:
                f.close()

        return StreamingResponse(file_iter(), media_type='audio/mpeg')
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
