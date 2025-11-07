from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from .core.config import get_settings
from .routers import recommend, tracks, health, auth, interactions, playlists, deezer, onboard, artists, chat, mood
from .core.db import engine, Base
from .core.db import SessionLocal
from .services.ml_recommendation_service import ml_recommendation_service

settings = get_settings()

app = FastAPI(title=settings.app_name, debug=settings.debug)


@app.middleware('http')
async def log_requests(request, call_next):
    try:
        auth = request.headers.get('authorization')
        print(f"[HTTP] {request.method} {request.url} Authorization: {auth}")
    except Exception:
        print(f"[HTTP] {request.method} {request.url} (no auth header)")
    response = await call_next(request)
    print(f"[HTTP] -> {response.status_code} {request.method} {request.url}")
    return response

# CORS: in dev accept any localhost/127.0.0.1 origin (any port). Tighten for prod.
if settings.debug:
    app.add_middleware(
        CORSMiddleware,
        allow_origin_regex=r"http://(localhost|127\.0\.0\.1)(:\d+)?",
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
else:
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:8000"],  # replace with real production origins
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )

@app.on_event("startup")
def on_startup():
    # Auto-create tables in dev (replace with Alembic in production)
    Base.metadata.create_all(bind=engine)
    # Ensure ML model is trained/loaded at startup (will retrain if metadata missing)
    try:
        db = SessionLocal()
        try:
            ml_recommendation_service.ensure_model_trained(db)
        finally:
            db.close()
    except Exception as e:
        print(f"⚠️  ML ensure_model_trained failed at startup: {e}")

app.include_router(health.router)
app.include_router(auth.router)
app.include_router(tracks.router)
app.include_router(interactions.router)
app.include_router(playlists.router)
app.include_router(recommend.router)
app.include_router(onboard.router)
app.include_router(artists.router)
app.include_router(chat.router)
app.include_router(mood.router)
# Spotify integration removed — spotify router disabled
app.include_router(deezer.router)

# Mount static assets (audio, covers)
app.mount('/static', StaticFiles(directory='app/static'), name='static')

@app.get("/")
async def root():
    return {"app": settings.app_name, "status": "running"}

@app.get("/_routes")
async def list_routes():
    routes = []
    for r in app.router.routes:
        try:
            path = getattr(r, 'path', None)
            name = getattr(r, 'name', None)
            methods = list(getattr(r, 'methods', []) or [])
            routes.append({"path": path, "name": name, "methods": methods})
        except Exception:
            continue
    return {"routes": routes}
