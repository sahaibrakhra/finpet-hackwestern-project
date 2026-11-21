"""End-to-end smoke test against a running server.

Usage (server already running, PROVIDER=mock):
    python scripts\\smoke_test.py [path\\to\\photo.jpg] [--base http://localhost:8000] [--timeout 300]
Without a photo, a synthetic test image is generated.
"""
from __future__ import annotations

import argparse
import io
import json
import struct
import sys
import time
from pathlib import Path

import requests
from PIL import Image, ImageDraw


def synthetic_photo() -> bytes:
    im = Image.new("RGB", (400, 600), (200, 210, 225))
    d = ImageDraw.Draw(im)
    d.ellipse((150, 60, 250, 180), fill=(224, 180, 150))
    d.rectangle((140, 190, 260, 420), fill=(60, 110, 190))
    d.rectangle((150, 420, 250, 570), fill=(50, 55, 75))
    buf = io.BytesIO()
    im.save(buf, "JPEG")
    return buf.getvalue()


def assert_valid_glb(data: bytes) -> dict:
    assert len(data) > 20, "GLB too small"
    magic, version, length = struct.unpack("<4sII", data[:12])
    assert magic == b"glTF", f"bad magic {magic!r}"
    assert version == 2, f"bad version {version}"
    assert length == len(data), f"header length {length} != actual {len(data)}"
    chunk_len, chunk_type = struct.unpack("<I4s", data[12:20])
    assert chunk_type == b"JSON", f"first chunk is {chunk_type!r}"
    gltf = json.loads(data[20:20 + chunk_len])
    assert gltf["asset"]["version"] == "2.0"
    assert gltf.get("meshes"), "GLB has no meshes"
    return gltf


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("photo", nargs="?")
    ap.add_argument("--base", default="http://localhost:8000")
    ap.add_argument("--timeout", type=float, default=300)
    args = ap.parse_args()
    base = args.base.rstrip("/")

    cfg = requests.get(f"{base}/api/config", timeout=10).json()
    print("config:", cfg)

    if args.photo:
        data, name = Path(args.photo).read_bytes(), Path(args.photo).name
    else:
        data, name = synthetic_photo(), "synthetic.jpg"
    r = requests.post(f"{base}/api/avatars", files={"photo": (name, data)}, timeout=30)
    assert r.status_code == 200, f"upload failed: {r.status_code} {r.text}"
    job_id = r.json()["job_id"]
    print("job:", job_id)

    # a bad upload must be rejected cleanly
    bad = requests.post(f"{base}/api/avatars", files={"photo": ("x.jpg", b"not an image")}, timeout=30)
    assert bad.status_code in (400, 415), f"bad file not rejected: {bad.status_code}"
    print("bad upload rejected:", bad.json()["detail"])

    seen, t0 = [], time.time()
    while True:
        j = requests.get(f"{base}/api/jobs/{job_id}", timeout=10).json()
        if not seen or seen[-1] != j["status"]:
            seen.append(j["status"])
            print(f"  [{j['elapsed_s']:6.1f}s] {j['status']}: {j['message']}")
        if j["status"] == "done":
            break
        assert j["status"] != "error", f"job failed: {j['error']}"
        assert time.time() - t0 < args.timeout, "timed out waiting for job"
        time.sleep(1)

    assert j["model_url"] == f"/api/models/{job_id}.glb", j["model_url"]
    g = requests.get(base + j["model_url"], timeout=30)
    assert g.status_code == 200, g.status_code
    gltf = assert_valid_glb(g.content)
    print(f"GLB ok: {len(g.content)} bytes, {len(gltf['meshes'])} meshes")

    lst = requests.get(f"{base}/api/avatars", timeout=10).json()
    assert any(a["id"] == job_id for a in lst), "avatar missing from list"
    print("listed in /api/avatars; stages seen:", seen)
    print("SMOKE TEST PASSED (avatar id kept: %s)" % job_id)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AssertionError as e:
        print("SMOKE TEST FAILED:", e)
        sys.exit(1)
