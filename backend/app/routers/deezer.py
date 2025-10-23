from fastapi import APIRouter, HTTPException, Depends, Request
from fastapi.responses import StreamingResponse, FileResponse
from typing import Optional
import requests
from ..services.deezer_service import search_tracks, get_track
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import Track
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
async def deezer_stream(track_id: int, request: Request, db: Session = Depends(get_db), cache: bool = True, refresh: bool = True):
    """Proxy Deezer track preview as a streaming response.

    This avoids CORS or referrer-based blocking on the client by serving the
    preview MP3 through our backend. Only previews (30s mp3) are proxied.
    """
    try:
        # Optionally refresh preview info from Deezer API on every play request.
        # This ensures we try to use a fresh signed preview URL before streaming.
        t = get_track(track_id) if refresh else None
        preview_url = None

        if t and t.get('preview'):
            preview_url = t.get('preview')
            # If we have a DB row, update stored preview_url if changed
            db_track = db.query(Track).filter(Track.id == track_id).first()
            if db_track and db_track.preview_url != preview_url:
                db_track.preview_url = preview_url
                db.add(db_track)
                db.commit()
        else:
            # Fallback: check local DB for a stored preview_url (from our fill script)
            db_track = db.query(Track).filter(Track.id == track_id).first()
            if db_track and db_track.preview_url:
                preview_url = db_track.preview_url
                # If stored preview is a relative path (eg '/tracks/{id}/preview'), build absolute URL
                if isinstance(preview_url, str) and preview_url.startswith('/'):
                    base = str(request.base_url).rstrip('/')
                    preview_url = base + preview_url
            else:
                raise HTTPException(status_code=404, detail='Preview not available')
        # Local cache path
        cache_dir = Path(__file__).resolve().parents[2] / 'app' / 'static' / 'audio' / 'deezer'
        cache_dir.mkdir(parents=True, exist_ok=True)
        cached_file = cache_dir / f'{track_id}.mp3'

        # If refresh-on-play is enabled and the cached file exists but the
        # stored preview URL differs from the freshly fetched preview URL,
        # invalidate the cache so we download the new preview.
        if refresh and cached_file.exists():
            try:
                db_track = db.query(Track).filter(Track.id == track_id).first()
                stored_preview = db_track.preview_url if db_track else None
                # If stored preview differs and the fresh preview_url is available, remove cache
                if stored_preview and preview_url and stored_preview != preview_url:
                    try:
                        cached_file.unlink()
                    except Exception:
                        pass
            except Exception:
                # If any error reading DB or removing file, ignore and continue; we'll attempt to re-download below
                pass

        if cache and not cached_file.exists():
            # Download preview into cache. Some CDNs block non-browser clients, so send
            # browser-like headers (User-Agent, Accept, Referer). If the first attempt
            # fails, retry once with a Referer header.
            headers_try = {
                'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.0.0 Safari/537.36',
                'Accept': 'audio/*,*/*'
            }
            tried = False
            success = False
            last_exc = None
            for attempt in range(2):
                try:
                    # add Referer on second attempt
                    if attempt == 1:
                        headers_try['Referer'] = 'https://www.deezer.com/'
                    with requests.get(preview_url, stream=True, timeout=15, headers=headers_try) as resp:
                        resp.raise_for_status()
                        tmp = cache_dir / f'{track_id}.tmp'
                        with tmp.open('wb') as fh:
                            shutil.copyfileobj(resp.raw, fh)
                        tmp.replace(cached_file)
                        success = True
                        break
                except requests.exceptions.HTTPError as he:
                    # Log upstream response when possible; keep last exception for later
                    last_exc = he
                    tried = True
                    resp = getattr(he, 'response', None)
                    # If upstream returned 403, attempt to refresh preview_url via Deezer API and retry once
                    if resp is not None and resp.status_code == 403:
                        try:
                            refreshed = get_track(track_id)
                            new_preview = None
                            if refreshed and refreshed.get('preview'):
                                new_preview = refreshed.get('preview')
                            # If we got a new preview different from the current one, update DB and retry
                            if new_preview and new_preview != preview_url:
                                db_track = db.query(Track).filter(Track.id == track_id).first()
                                if db_track:
                                    db_track.preview_url = new_preview
                                    db.add(db_track)
                                    db.commit()
                                preview_url = new_preview
                                # retry current attempt with updated preview_url by continuing the loop
                                continue
                            # otherwise surface a clearer 403 to client
                            body = None
                            try:
                                body = resp.content.decode('utf-8', errors='replace')
                            except Exception:
                                body = '<binary or undecodable body>'
                            raise HTTPException(status_code=403, detail=f'Upstream CDN returned 403 for preview. Upstream body: {body[:400]}')
                        except HTTPException:
                            raise
                        except Exception:
                            # if refresh failed, re-raise original HTTPError as 502
                            raise HTTPException(status_code=502, detail=str(he))
                except Exception as e:
                    last_exc = e
                    tried = True

            if not success:
                # If caching fails, fall back to proxy streaming with browser-like headers.
                # This may still fail if the preview URL token is expired.
                try:
                    if 'Referer' not in headers_try:
                        headers_try['Referer'] = 'https://www.deezer.com/'
                    resp = requests.get(preview_url, stream=True, timeout=15, headers=headers_try)
                    resp.raise_for_status()
                    # If caching is disabled, stream directly from upstream
                    if not cache:
                        headers = {}
                        if 'content-length' in resp.headers:
                            headers['Content-Length'] = resp.headers['content-length']
                        content_type = resp.headers.get('content-type', 'audio/mpeg')
                        return StreamingResponse(resp.iter_content(chunk_size=1024), media_type=content_type, headers=headers)
                    # otherwise the previous code handled writing to tmp -> cached_file and will fallthrough to serve disk file
                except requests.exceptions.HTTPError as he:
                    resp = getattr(he, 'response', None)
                    # If 403, try to refresh preview via Deezer API and retry once
                    if resp is not None and resp.status_code == 403:
                        try:
                            refreshed = get_track(track_id)
                            new_preview = None
                            if refreshed and refreshed.get('preview'):
                                new_preview = refreshed.get('preview')
                            if new_preview and new_preview != preview_url:
                                db_track = db.query(Track).filter(Track.id == track_id).first()
                                if db_track:
                                    db_track.preview_url = new_preview
                                    db.add(db_track)
                                    db.commit()
                                preview_url = new_preview
                                # Try one direct proxy with the refreshed URL
                                try:
                                    headers_try['Referer'] = 'https://www.deezer.com/'
                                    resp2 = requests.get(preview_url, stream=True, timeout=15, headers=headers_try)
                                    resp2.raise_for_status()
                                    if not cache:
                                        headers = {}
                                        if 'content-length' in resp2.headers:
                                            headers['Content-Length'] = resp2.headers['content-length']
                                        content_type = resp2.headers.get('content-type', 'audio/mpeg')
                                        return StreamingResponse(resp2.iter_content(chunk_size=1024), media_type=content_type, headers=headers)
                                    # if cache enabled, write to disk below via normal path
                                except Exception as e:
                                    raise HTTPException(status_code=502, detail=str(e))
                            # if no new preview, raise clearer 403
                            body = None
                            try:
                                body = resp.content.decode('utf-8', errors='replace')
                            except Exception:
                                body = '<binary or undecodable body>'
                            raise HTTPException(status_code=403, detail=f'Upstream CDN returned 403 for preview. Upstream body: {body[:400]}')
                        except HTTPException:
                            raise
                        except Exception as e:
                            raise HTTPException(status_code=502, detail=str(e))
                    # re-raise as a 502 to indicate bad gateway for other HTTP errors
                    raise HTTPException(status_code=502, detail=str(he))
                except Exception as e:
                    # Unknown local error while proxying
                    raise HTTPException(status_code=500, detail=str(e))

        # Serve cached file as a FileResponse so framework can set Content-Length
        # and support range requests (seek) reliably for clients.
        try:
            return FileResponse(str(cached_file), media_type='audio/mpeg', headers={'Accept-Ranges': 'bytes'})
        except Exception:
            # Fallback to streaming if FileResponse fails for any reason
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
