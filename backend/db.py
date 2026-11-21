"""Thin Supabase (PostgREST) client using the service role key. Server-side only."""
import os

import httpx
from fastapi import HTTPException


class UsernameTaken(Exception):
    pass


def _config() -> tuple[str, dict]:
    url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
    key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
    if not url or not key:
        raise HTTPException(
            503, "Accounts are unavailable: server is missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY."
        )
    return f"{url}/rest/v1", {"apikey": key, "Authorization": f"Bearer {key}"}


def is_configured() -> bool:
    return bool(os.getenv("SUPABASE_URL", "").strip() and os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip())


def _request(method: str, table: str, *, params=None, json=None, prefer: str | None = None) -> httpx.Response:
    base, headers = _config()
    if prefer:
        headers["Prefer"] = prefer
    try:
        return httpx.request(method, f"{base}/{table}", params=params, json=json, headers=headers, timeout=10)
    except httpx.HTTPError:
        raise HTTPException(503, "Could not reach the accounts database. Try again shortly.")


def _check(r: httpx.Response) -> None:
    if r.status_code >= 400:
        raise HTTPException(503, "The accounts database returned an error. Try again shortly.")


def get_user_by_username(username: str) -> dict | None:
    r = _request("GET", "users", params={"username": f"eq.{username}", "select": "id,username,password_hash"})
    _check(r)
    rows = r.json()
    return rows[0] if rows else None


def get_user_by_id(user_id: str) -> dict | None:
    r = _request("GET", "users", params={"id": f"eq.{user_id}", "select": "id,username"})
    _check(r)
    rows = r.json()
    return rows[0] if rows else None


def create_user(username: str, password_hash: str) -> dict:
    r = _request(
        "POST", "users", json={"username": username, "password_hash": password_hash},
        prefer="return=representation",
    )
    if r.status_code == 409:
        raise UsernameTaken()
    _check(r)
    row = r.json()[0]
    return {"id": row["id"], "username": row["username"]}


def touch_last_login(user_id: str) -> None:
    """Best effort; a failure here must not block login."""
    try:
        from datetime import datetime, timezone

        _request("PATCH", "users", params={"id": f"eq.{user_id}"},
                 json={"last_login_at": datetime.now(timezone.utc).isoformat()})
    except HTTPException:
        pass
