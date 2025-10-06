from fastapi import APIRouter, Depends, HTTPException, status, Request
from pydantic import BaseModel, EmailStr
from sqlalchemy.orm import Session
from ..core.db import get_db
from ..models.music import User
from ..core.security import hash_password, verify_password, create_access_token, decode_token

router = APIRouter(prefix="/auth", tags=["auth"])

class RegisterRequest(BaseModel):
    email: EmailStr
    password: str
    display_name: str | None = None

class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    user_id: int

class LoginRequest(BaseModel):
    email: EmailStr
    password: str

class MeResponse(BaseModel):
    id: int
    email: EmailStr
    display_name: str | None = None

@router.post('/register', response_model=TokenResponse)
async def register(request: Request, db: Session = Depends(get_db)):
    """Flexible register like login: accepts JSON or form fields."""
    data = {}
    try:
        data = await request.json()
        if not isinstance(data, dict):
            data = {}
    except Exception:
        try:
            form = await request.form()
            data = dict(form)
        except Exception:
            data = {}

    email = data.get('email') or data.get('username')
    password = data.get('password')
    display_name = data.get('display_name') if isinstance(data, dict) else None
    if not email or not password:
        raise HTTPException(status_code=400, detail="Missing email and/or password")

    existing = db.query(User).filter(User.email == email).first()
    if existing:
        raise HTTPException(status_code=400, detail="Email already registered")
    user = User(email=email, password_hash=hash_password(password), display_name=display_name)
    db.add(user)
    db.commit()
    db.refresh(user)
    token = create_access_token(str(user.id))
    return TokenResponse(access_token=token, user_id=user.id)

@router.post('/login', response_model=TokenResponse)
async def login(request: Request, db: Session = Depends(get_db)):
    """Flexible login endpoint.
    Accepts either:
      - JSON body: {"email": "...", "password": "..."}
      - Form-encoded body (legacy / browser fallback): email=...&password=...
      - Also supports 'username' in place of 'email' for compatibility with earlier tests.
    This mitigates client issues where JSON quoting or headers are malformed.
    """
    data = {}
    # Try JSON first
    try:
        data = await request.json()
        if not isinstance(data, dict):
            data = {}
    except Exception:
        # Fallback to form
        try:
            form = await request.form()
            data = dict(form)
        except Exception:
            data = {}

    email = (data.get('email') or data.get('username')) if isinstance(data, dict) else None
    password = data.get('password') if isinstance(data, dict) else None
    if not email or not password:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Missing email/username or password")

    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(password, user.password_hash):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    token = create_access_token(str(user.id))
    return TokenResponse(access_token=token, user_id=user.id)

@router.post('/login_raw')
async def login_raw_debug(request: Request):
    """Debug endpoint: echo raw body & content type to diagnose JSON parse issues."""
    body_bytes = await request.body()
    return {
        "content_type": request.headers.get('content-type'),
        "raw_body": body_bytes.decode(errors='replace'),
        "length": len(body_bytes)
    }

def _get_current_user(request: Request, db: Session) -> User:
    auth_header = request.headers.get('authorization') or request.headers.get('Authorization')
    if not auth_header or not auth_header.lower().startswith('bearer '):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Not authenticated")
    token = auth_header.split(' ', 1)[1].strip()
    sub = decode_token(token)
    if not sub:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Token invalid or expired")
    user = db.query(User).filter(User.id == int(sub)).first()
    if not user:
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="User not found")
    return user

@router.get('/me', response_model=MeResponse)
async def me(request: Request, db: Session = Depends(get_db)):
    user = _get_current_user(request, db)
    return MeResponse(id=user.id, email=user.email, display_name=user.display_name)
