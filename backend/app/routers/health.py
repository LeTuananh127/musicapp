from fastapi import APIRouter

router = APIRouter(prefix="/health", tags=["health"])

@router.get("/ping")
async def ping():
    """Canonical health check endpoint.

    Returns a simple status payload used by external monitors.
    """
    return {"status": "ok"}

@router.get("")
async def root_health():
    """Alias to match older documentation that referenced GET /health.

    Some tooling probes /health by default, so we expose both /health and
    /health/ping returning the same payload.
    """
    return {"status": "ok"}
