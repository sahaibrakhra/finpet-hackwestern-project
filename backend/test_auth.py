"""Auth logic tests with the DB layer mocked (no network). Run: pytest (from backend/)."""
import time
from datetime import datetime, timedelta, timezone

import jwt
import pytest
from fastapi.testclient import TestClient

import auth
import db
import main

SECRET = "x" * 48


class FakeDB:
    def __init__(self):
        self.users = {}

    def create_user(self, username, password_hash):
        if username in self.users:
            raise db.UsernameTaken()
        u = {"id": f"id-{len(self.users) + 1}", "username": username, "password_hash": password_hash}
        self.users[username] = u
        return {"id": u["id"], "username": username}

    def get_user_by_username(self, username):
        return self.users.get(username)

    def get_user_by_id(self, uid):
        return next((u for u in self.users.values() if u["id"] == uid), None)

    def touch_last_login(self, uid):
        pass


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", SECRET)
    monkeypatch.setattr(auth, "BCRYPT_COST", 4)  # fast tests
    fake = FakeDB()
    for name in ("create_user", "get_user_by_username", "get_user_by_id", "touch_last_login"):
        monkeypatch.setattr(db, name, getattr(fake, name))
    return TestClient(main.app)


def creds(u="Alice_1", p="correcthorse"):
    return {"username": u, "password": p}


def test_register_login_me(client):
    r = client.post("/api/auth/register", json=creds())
    assert r.status_code == 200
    body = r.json()
    assert body["user"] == {"id": "id-1", "username": "alice_1"}
    claims = jwt.decode(body["token"], SECRET, algorithms=["HS256"])
    assert claims["exp"] - claims["iat"] == 7 * 86400
    assert body["expires_at"].endswith("Z")

    r = client.post("/api/auth/login", json=creds("ALICE_1"))
    assert r.status_code == 200
    token = r.json()["token"]
    me = client.get("/api/auth/me", headers={"Authorization": f"Bearer {token}"})
    assert me.status_code == 200 and me.json() == {"id": "id-1", "username": "alice_1"}


def test_password_stored_hashed(client):
    client.post("/api/auth/register", json=creds())
    h = db.get_user_by_username("alice_1")["password_hash"]
    assert h.startswith("$2") and "correcthorse" not in h


def test_duplicate_username_409(client):
    client.post("/api/auth/register", json=creds("Bob"))
    r = client.post("/api/auth/register", json=creds("bOB"))
    assert r.status_code == 409 and "detail" in r.json()


@pytest.mark.parametrize("u", ["ab", "a" * 21, "bad name", "emoji😀x", "dash-ed", ""])
def test_bad_username_400(client, u):
    assert client.post("/api/auth/register", json=creds(u)).status_code == 400


@pytest.mark.parametrize("p", ["short", "a" * 73, "é" * 40])
def test_bad_password_400(client, p):
    assert client.post("/api/auth/register", json=creds("carol", p)).status_code == 400


def test_login_failures_are_identical(client):
    client.post("/api/auth/register", json=creds("dave"))
    wrong = client.post("/api/auth/login", json=creds("dave", "wrongpassword"))
    unknown = client.post("/api/auth/login", json=creds("nobody", "wrongpassword"))
    long = client.post("/api/auth/login", json=creds("dave", "a" * 200))
    for r in (wrong, unknown, long):
        assert r.status_code == 401 and r.json() == {"detail": "Invalid username or password."}


def test_me_rejects_bad_tokens(client):
    assert client.get("/api/auth/me").status_code == 401
    assert client.get("/api/auth/me", headers={"Authorization": "Bearer junk"}).status_code == 401
    client.post("/api/auth/register", json=creds("erin"))
    past = datetime.now(timezone.utc) - timedelta(seconds=5)
    expired = jwt.encode({"sub": "id-1", "exp": past}, SECRET, algorithm="HS256")
    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {expired}"}).status_code == 401
    forged = jwt.encode({"sub": "id-1", "exp": time.time() + 999}, "y" * 48, algorithm="HS256")
    assert client.get("/api/auth/me", headers={"Authorization": f"Bearer {forged}"}).status_code == 401


def test_503_without_config_and_health_ok(monkeypatch):
    for k in ("JWT_SECRET", "SUPABASE_URL", "SUPABASE_SERVICE_ROLE_KEY"):
        monkeypatch.delenv(k, raising=False)
    c = TestClient(main.app)
    assert c.get("/health").status_code == 200
    r = c.post("/api/auth/register", json=creds())
    assert r.status_code == 503 and "detail" in r.json()
    assert c.post("/api/auth/login", json=creds()).status_code == 503
    monkeypatch.setenv("JWT_SECRET", SECRET)
    r = c.post("/api/auth/register", json=creds())
    assert r.status_code == 503 and "SUPABASE" in r.json()["detail"]
