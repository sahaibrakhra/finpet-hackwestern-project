"""Friends: send/accept/deny requests, list friends, remove a friend. All routes need a login token.

A friendship row is directed requester -> addressee. Until the addressee accepts it is 'pending' and
neither side counts as a friend. Accepting flips it to 'accepted' (mutual) and creates the pair's
friend_streaks row; denying or removing deletes the rows, so the pair can request each other again.
"""
import uuid
from datetime import datetime, timezone

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel

import auth
import db

router = APIRouter(prefix="/api/friends", tags=["friends"])


class RequestBody(BaseModel):
    username: str


def _uuid(value: str) -> str:
    try:
        return str(uuid.UUID(value))
    except ValueError:
        raise HTTPException(404, "Not found.")


# --- data layer (PostgREST); the routes below only use these, so tests can swap them ------

def _rows(table: str, params: dict) -> list[dict]:
    r = db._request("GET", table, params=params)
    db._check(r)
    return r.json()


def _or_me(uid: str, a: str, b: str) -> str:
    return f"({a}.eq.{uid},{b}.eq.{uid})"


def list_friendships(uid: str) -> list[dict]:
    return _rows("friendships", {
        "or": _or_me(uid, "requester_id", "addressee_id"),
        "select": "id,requester_id,addressee_id,status",
    })


def get_friendship(fid: str) -> dict | None:
    rows = _rows("friendships", {"id": f"eq.{fid}", "select": "id,requester_id,addressee_id,status"})
    return rows[0] if rows else None


def usernames(ids: list[str]) -> dict[str, str]:
    if not ids:
        return {}
    rows = _rows("users", {"id": f"in.({','.join(ids)})", "select": "id,username"})
    return {row["id"]: row["username"] for row in rows}


def streaks(uid: str) -> dict[str, int]:
    """other user's id -> current shared streak."""
    out = {}
    for row in _rows("friend_streaks", {
        "or": _or_me(uid, "user_a_id", "user_b_id"),
        "select": "user_a_id,user_b_id,current_streak",
    }):
        other = row["user_b_id"] if row["user_a_id"] == uid else row["user_a_id"]
        out[other] = row["current_streak"]
    return out


def create_request(requester: str, addressee: str) -> None:
    r = db._request("POST", "friendships", json={"requester_id": requester, "addressee_id": addressee})
    if r.status_code == 409:
        raise HTTPException(409, "You already have a request or friendship with that user.")
    db._check(r)


def accept_request(fid: str, requester: str, addressee: str) -> None:
    now = datetime.now(timezone.utc).isoformat()
    r = db._request("PATCH", "friendships", params={"id": f"eq.{fid}"},
                    json={"status": "accepted", "responded_at": now})
    db._check(r)
    a, b = sorted([requester, addressee])
    r = db._request("POST", "friend_streaks", json={"user_a_id": a, "user_b_id": b},
                    prefer="resolution=ignore-duplicates")
    db._check(r)


def delete_friendship(fid: str, requester: str, addressee: str) -> None:
    a, b = sorted([requester, addressee])
    db._check(db._request("DELETE", "friend_streaks", params={"user_a_id": f"eq.{a}", "user_b_id": f"eq.{b}"}))
    db._check(db._request("DELETE", "friendships", params={"id": f"eq.{fid}"}))


# --- routes -------------------------------------------------------------------------------

@router.get("")
def overview(user: dict = Depends(auth.get_current_user)) -> dict:
    me = user["id"]
    rows = list_friendships(me)
    others = {r["addressee_id"] if r["requester_id"] == me else r["requester_id"] for r in rows}
    names = usernames(sorted(others))
    shared = streaks(me)
    friends, incoming, outgoing = [], [], []
    for r in rows:
        mine = r["requester_id"] == me
        other = r["addressee_id"] if mine else r["requester_id"]
        entry = {"id": other, "username": names.get(other, "unknown")}
        if r["status"] == "accepted":
            friends.append({**entry, "streak": shared.get(other, 0)})
        elif r["status"] == "pending":
            (outgoing if mine else incoming).append({"request_id": r["id"], **entry})
    friends.sort(key=lambda f: f["username"])
    return {"friends": friends, "incoming": incoming, "outgoing": outgoing}


@router.post("/requests")
def send_request(body: RequestBody, user: dict = Depends(auth.get_current_user)) -> dict:
    name = auth.validate_username(body.username.strip())
    if name == user["username"]:
        raise HTTPException(400, "You can't add yourself.")
    target = db.get_user_by_username(name)
    if target is None:
        raise HTTPException(404, f'No user named "{name}".')
    existing = [r for r in list_friendships(user["id"])
                if target["id"] in (r["requester_id"], r["addressee_id"])]
    if existing:
        row = existing[0]
        if row["status"] == "accepted":
            raise HTTPException(409, f"You and {name} are already friends.")
        if row["requester_id"] == user["id"]:
            raise HTTPException(409, f"You already sent {name} a request.")
        raise HTTPException(409, f"{name} already sent you a request. Check your notifications.")
    create_request(user["id"], target["id"])
    return {"ok": True, "username": name}


def _pending_for_me(request_id: str, user: dict) -> dict:
    row = get_friendship(_uuid(request_id))
    if row is None or row["status"] != "pending" or row["addressee_id"] != user["id"]:
        raise HTTPException(404, "That request no longer exists.")
    return row


@router.post("/requests/{request_id}/accept")
def accept(request_id: str, user: dict = Depends(auth.get_current_user)) -> dict:
    row = _pending_for_me(request_id, user)
    accept_request(row["id"], row["requester_id"], row["addressee_id"])
    return {"ok": True}


@router.post("/requests/{request_id}/deny")
def deny(request_id: str, user: dict = Depends(auth.get_current_user)) -> dict:
    row = _pending_for_me(request_id, user)
    delete_friendship(row["id"], row["requester_id"], row["addressee_id"])
    return {"ok": True}


@router.delete("/{friend_id}")
def remove(friend_id: str, user: dict = Depends(auth.get_current_user)) -> dict:
    other = _uuid(friend_id)
    for row in list_friendships(user["id"]):
        if row["status"] == "accepted" and other in (row["requester_id"], row["addressee_id"]):
            delete_friendship(row["id"], row["requester_id"], row["addressee_id"])
            return {"ok": True}
    raise HTTPException(404, "That user is not in your friends list.")
