from datetime import datetime, timedelta
from typing import Optional
import jwt
from passlib.context import CryptContext
from .config import get_settings

# Use pbkdf2_sha256 as stable primary (pure python, no platform wheel issues) and keep bcrypt as fallback
# for any existing hashes that may already be stored. This avoids Windows bcrypt backend errors while
# allowing future migration. Newly created hashes will use pbkdf2_sha256.
pwd_context = CryptContext(schemes=["pbkdf2_sha256", "bcrypt"], deprecated="auto")
settings = get_settings()
ALGORITHM = "HS256"
ACCESS_TOKEN_EXPIRE_MINUTES = 60 * 12

def hash_password(password: str) -> str:
    # Normalize whitespace before hashing
    pw = password.strip()
    return pwd_context.hash(pw)

def verify_password(password: str, hashed: str) -> bool:
    try:
        return pwd_context.verify(password.strip(), hashed)
    except Exception:
        return False

def create_access_token(sub: str, expires_minutes: int = ACCESS_TOKEN_EXPIRE_MINUTES) -> str:
    expire = datetime.utcnow() + timedelta(minutes=expires_minutes)
    payload = {"sub": sub, "exp": expire}
    return jwt.encode(payload, settings.jwt_secret, algorithm=ALGORITHM)

def decode_token(token: str) -> Optional[str]:
    try:
        data = jwt.decode(token, settings.jwt_secret, algorithms=[ALGORITHM])
        return data.get("sub")
    except Exception:
        return None
