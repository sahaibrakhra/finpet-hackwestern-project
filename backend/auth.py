"""Accounts: register / login / me, bcrypt password hashing, HS256 JWTs, get_current_user dependency."""
import logging
import os
import re
from datetime import datetime, timedelta, timezone

import bcrypt
import jwt
from fastapi import APIRouter, Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from pydantic import BaseModel

import db

log = logging.getLogger("finpet.auth")

router = APIRouter(prefix="/api/auth", tags=["auth"])

BCRYPT_COST = 12
USERNAME_RE = re.compile(r"^[A-Za-z0-9_]{3,20}$")
PASSWORD_MIN, PASSWORD_MAX = 8, 72
INVALID_LOGIN = "Invalid username or password."

# Hash of a random value, checked when the username is unknown so timing doesn't reveal it.
_DUMMY_HASH = bcrypt.hashpw(os.urandom(16).hex().encode(), bcrypt.gensalt(BCRYPT_COST))

_bearer = HTTPBearer(auto_error=False)


class Credentials(BaseModel):
    username: str
    password: str


# --- validation --------------------------------------------------------------------------

def validate_username(username: str) -> str:
    """Return the normalised (lowercase) username or raise 400."""
    if not USERNAME_RE.fullmatch(username):
        raise HTTPException(400, "Username must be 3-20 characters: letters, numbers and underscores only.")
    return username.lower()


def validate_password(password: str) -> None:
    if len(password) < PASSWORD_MIN:
        raise HTTPException(400, f"Password must be at least {PASSWORD_MIN} characters.")
    if len(password) > PASSWORD_MAX or len(password.encode("utf-8")) > PASSWORD_MAX:
        raise HTTPException(400, f"Password must be at most {PASSWORD_MAX} bytes (shorter if it uses emoji or accents).")


# --- hashing -----------------------------------------------------------------------------

def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt(BCRYPT_COST)).decode()


def verify_password(password: str, password_hash: str | bytes | None) -> bool:
    """Always performs one bcrypt check (against a dummy hash if there is no real one)."""
    if isinstance(password_hash, str):
        password_hash = password_hash.encode()
    pw = password.encode("utf-8")
    if len(pw) > PASSWORD_MAX:  # bcrypt can't take it; it can't match a stored hash either
        bcrypt.checkpw(b"x", _DUMMY_HASH)
        return False
    ok = bcrypt.checkpw(pw, password_hash or _DUMMY_HASH)
    return ok and password_hash is not None


# --- tokens ------------------------------------------------------------------------------

def _jwt_secret() -> str:
    secret = os.getenv("JWT_SECRET", "").strip()
    if len(secret) < 32:
        raise HTTPException(503, "Accounts are unavailable: server JWT_SECRET is missing or too short (min 32 chars).")
    return secret


def _expire_days() -> float:
    try:
        return float(os.getenv("JWT_EXPIRE_DAYS", "").strip() or 7)
    except ValueError:
        return 7


def create_token(user_id: str, username: str) -> tuple[str, datetime]:
    now = datetime.now(timezone.utc).replace(microsecond=0)
    expires = now + timedelta(days=_expire_days())
    claims = {"sub": user_id, "username": username, "iat": now, "exp": expires}
    return jwt.encode(claims, _jwt_secret(), algorithm="HS256"), expires


def decode_token(token: str) -> dict:
    """Return the claims or raise 401."""
    try:
        return jwt.decode(token, _jwt_secret(), algorithms=["HS256"], options={"require": ["exp", "sub"]})
    except jwt.PyJWTError:
        raise HTTPException(401, "Invalid or expired token.", headers={"WWW-Authenticate": "Bearer"})


def _session(user: dict) -> dict:
    token, expires = create_token(user["id"], user["username"])
    return {
        "token": token,
        "expires_at": expires.strftime("%Y-%m-%dT%H:%M:%SZ"),
        "user": {"id": user["id"], "username": user["username"]},
    }


# --- dependency for protected routes -----------------------------------------------------

def get_current_user(creds: HTTPAuthorizationCredentials | None = Depends(_bearer)) -> dict:
    """Usage: `user: dict = Depends(get_current_user)` -> {"id": str, "username": str}."""
    if creds is None:
        raise HTTPException(401, "Missing bearer token.", headers={"WWW-Authenticate": "Bearer"})
    claims = decode_token(creds.credentials)
    user = db.get_user_by_id(claims["sub"])
    if user is None:
        raise HTTPException(401, "Invalid or expired token.", headers={"WWW-Authenticate": "Bearer"})
    return {"id": user["id"], "username": user["username"]}


# --- routes ------------------------------------------------------------------------------

@router.post("/register")
def register(body: Credentials) -> dict:
    username = validate_username(body.username)
    validate_password(body.password)
    _jwt_secret()  # fail with 503 before creating a user we can't issue a token for
    try:
        user = db.create_user(username, hash_password(body.password))
    except db.UsernameTaken:
        raise HTTPException(409, "That username is already taken.")
    return _session(user)


@router.post("/login")
def login(body: Credentials) -> dict:
    _jwt_secret()
    username = body.username.strip().lower()
    user = db.get_user_by_username(username) if USERNAME_RE.fullmatch(username) else None
    ok = verify_password(body.password, user["password_hash"] if user else None)
    if not user or not ok:
        raise HTTPException(401, INVALID_LOGIN)
    db.touch_last_login(user["id"])
    return _session(user)


@router.get("/me")
def me(user: dict = Depends(get_current_user)) -> dict:
    return user
