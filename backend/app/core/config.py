from pydantic import BaseModel
import os
from functools import lru_cache
from dotenv import load_dotenv

load_dotenv()

class Settings(BaseModel):
    app_name: str = "Music Recommender API"
    debug: bool = True
    # default points to MySQL musicdb (user created earlier). Use mysql+mysqldb explicit dialect.
    database_url: str = os.getenv("DATABASE_URL", "mysql+mysqldb://musicapp:1234@localhost:3306/musicdb")
    jwt_secret: str = os.getenv("JWT_SECRET", "dev-secret")
    model_dir: str = os.getenv("MODEL_DIR", "app/ml/artifacts")
    # optional: enable sqlite fallback quickly when MYSQL_DISABLED=1
    sqlite_fallback: bool = bool(int(os.getenv("MYSQL_DISABLED", "0")))
    # Spotify API credentials (optional): set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET in env
    spotify_client_id: str | None = os.getenv('SPOTIFY_CLIENT_ID')
    spotify_client_secret: str | None = os.getenv('SPOTIFY_CLIENT_SECRET')

    model_config = {
        'protected_namespaces': ()  # allow field name model_dir without warning
    }

@lru_cache
def get_settings() -> Settings:
    s = Settings()
    if s.sqlite_fallback and s.database_url.startswith("mysql"):
        # switch to local sqlite file if fallback flag set
        s.database_url = "sqlite:///./dev.db"
    return s
