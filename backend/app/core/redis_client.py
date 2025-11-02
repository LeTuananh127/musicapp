from redis import Redis
from .config import get_settings

_settings = get_settings()

_redis = None

def get_redis() -> Redis:
    global _redis
    if _redis is None:
        _redis = Redis(host=_settings.redis_host, port=_settings.redis_port, db=_settings.redis_db)
    return _redis
