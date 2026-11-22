"""Friends flow with an in-memory fake data layer (no network). Run: pytest (from backend/)."""
import uuid

import pytest
from fastapi.testclient import TestClient

import auth
import db
import friends
import main

SECRET = "x" * 48


class Fake:
    def __init__(self):
        self.users = {}  # username -> {id, username}
        self.rows = []   # friendships
        self.streak_rows = set()

    def add_user(self, name):
        self.users[name] = {"id": str(uuid.uuid4()), "username": name}
        return self.users[name]

    def get_user_by_username(self, name):
        return self.users.get(name)

    def get_user_by_id(self, uid):
        return next((u for u in self.users.values() if u["id"] == uid), None)

    def list_friendships(self, uid):
        return [dict(r) for r in self.rows if uid in (r["requester_id"], r["addressee_id"])]

    def get_friendship(self, fid):
        return next((dict(r) for r in self.rows if r["id"] == fid), None)

    def usernames(self, ids):
        return {u["id"]: u["username"] for u in self.users.values() if u["id"] in ids}

    def streaks(self, uid):
        return {}

    def create_request(self, a, b):
        self.rows.append({"id": str(uuid.uuid4()), "requester_id": a, "addressee_id": b, "status": "pending"})

    def accept_request(self, fid, a, b):
        next(r for r in self.rows if r["id"] == fid)["status"] = "accepted"
        self.streak_rows.add(tuple(sorted([a, b])))

    def delete_friendship(self, fid, a, b):
        self.rows = [r for r in self.rows if r["id"] != fid]
        self.streak_rows.discard(tuple(sorted([a, b])))


def header(user):
    return {"Authorization": "Bearer " + auth.create_token(user["id"], user["username"])[0]}


@pytest.fixture
def env(monkeypatch):
    monkeypatch.setenv("JWT_SECRET", SECRET)
    fake = Fake()
    monkeypatch.setattr(db, "get_user_by_username", fake.get_user_by_username)
    monkeypatch.setattr(db, "get_user_by_id", fake.get_user_by_id)
    for name in ("list_friendships", "get_friendship", "usernames", "streaks", "create_request",
                 "accept_request", "delete_friendship"):
        monkeypatch.setattr(friends, name, getattr(fake, name))
    alice, bob = fake.add_user("alice"), fake.add_user("bob")
    return TestClient(main.app), fake, alice, bob, header(alice), header(bob)


def test_request_accept_remove(env):
    c, fake, alice, bob, ha, hb = env
    assert c.post("/api/friends/requests", json={"username": "Bob"}, headers=ha).status_code == 200
    # Pending: nobody is a friend yet; bob sees it as incoming, alice as outgoing.
    a, b = c.get("/api/friends", headers=ha).json(), c.get("/api/friends", headers=hb).json()
    assert a["friends"] == [] and len(a["outgoing"]) == 1 and a["incoming"] == []
    assert b["friends"] == [] and b["incoming"][0]["username"] == "alice"
    rid = b["incoming"][0]["request_id"]
    # Only the addressee can accept.
    assert c.post(f"/api/friends/requests/{rid}/accept", headers=ha).status_code == 404
    assert c.post(f"/api/friends/requests/{rid}/accept", headers=hb).status_code == 200
    for h, other in ((ha, "bob"), (hb, "alice")):
        data = c.get("/api/friends", headers=h).json()
        assert [f["username"] for f in data["friends"]] == [other]
        assert not data["incoming"] and not data["outgoing"]
    assert len(fake.streak_rows) == 1
    assert c.delete(f"/api/friends/{bob['id']}", headers=ha).status_code == 200
    assert c.get("/api/friends", headers=hb).json()["friends"] == []
    assert not fake.streak_rows
    assert c.delete(f"/api/friends/{bob['id']}", headers=ha).status_code == 404


def test_deny_allows_rerequest(env):
    c, fake, alice, bob, ha, hb = env
    c.post("/api/friends/requests", json={"username": "bob"}, headers=ha)
    rid = c.get("/api/friends", headers=hb).json()["incoming"][0]["request_id"]
    assert c.post(f"/api/friends/requests/{rid}/deny", headers=hb).status_code == 200
    assert c.get("/api/friends", headers=hb).json()["incoming"] == []
    assert c.post("/api/friends/requests", json={"username": "bob"}, headers=ha).status_code == 200


def test_request_errors(env):
    c, fake, alice, bob, ha, hb = env
    assert c.post("/api/friends/requests", json={"username": "nobody"}, headers=ha).status_code == 404
    assert c.post("/api/friends/requests", json={"username": "alice"}, headers=ha).status_code == 400
    assert c.post("/api/friends/requests", json={"username": "!!"}, headers=ha).status_code == 400
    c.post("/api/friends/requests", json={"username": "bob"}, headers=ha)
    assert c.post("/api/friends/requests", json={"username": "bob"}, headers=ha).status_code == 409
    assert c.post("/api/friends/requests", json={"username": "alice"}, headers=hb).status_code == 409
    assert c.get("/api/friends").status_code == 401
    assert c.post("/api/friends/requests/not-a-uuid/accept", headers=hb).status_code == 404
