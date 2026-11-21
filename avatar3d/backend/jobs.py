"""Thread-safe job store persisted to storage/jobs.json."""
from __future__ import annotations

import json
import logging
import os
import threading
import time
import uuid
from pathlib import Path
from typing import Optional

log = logging.getLogger("avatar3d.jobs")

TERMINAL = {"done", "error"}
JOB_TIMEOUT_S = float(os.getenv("JOB_TIMEOUT_S", "600"))


class JobStore:
    def __init__(self, path: Path) -> None:
        self.path = path
        self._lock = threading.RLock()
        self._jobs: dict[str, dict] = {}
        self._load()

    # -- persistence -------------------------------------------------------
    def _load(self) -> None:
        if not self.path.exists():
            return
        try:
            data = json.loads(self.path.read_text(encoding="utf-8"))
            self._jobs = {j["id"]: j for j in data.get("jobs", [])}
        except Exception as e:  # noqa: BLE001
            log.error("Could not read %s (%s); starting empty", self.path, e)
            try:
                self.path.replace(self.path.with_suffix(".json.corrupt"))
            except OSError:
                pass
            return
        now = time.time()
        changed = False
        for j in self._jobs.values():
            if j["status"] not in TERMINAL:
                j.update(status="error", finished_at=now, error="The server restarted while this job was running. Please try again.",
                         message="Interrupted by server restart.")
                changed = True
        if changed:
            self._save()

    def _save(self) -> None:
        tmp = self.path.with_suffix(".json.tmp")
        tmp.write_text(json.dumps({"jobs": list(self._jobs.values())}, indent=1), encoding="utf-8")
        os.replace(tmp, self.path)

    # -- API ---------------------------------------------------------------
    def create(self, provider: str, job_id: Optional[str] = None) -> dict:
        with self._lock:
            job = {
                "id": job_id or uuid.uuid4().hex[:12],
                "status": "queued",
                "message": "Queued.",
                "created_at": time.time(),
                "finished_at": None,
                "provider": provider,
                "has_thumbnail": False,
                "error": None,
            }
            self._jobs[job["id"]] = job
            self._save()
            return dict(job)

    def update(self, job_id: str, **fields) -> None:
        """Update a non-terminal job. Silently ignored once the job is done/error
        (so a timed-out job's worker thread cannot resurrect it)."""
        with self._lock:
            job = self._jobs.get(job_id)
            if not job or job["status"] in TERMINAL:
                return
            job.update(fields)
            if fields.get("status") in TERMINAL:
                job["finished_at"] = time.time()
            self._save()

    def fail(self, job_id: str, error: str) -> None:
        self.update(job_id, status="error", message=error, error=error)

    def is_active(self, job_id: str) -> bool:
        with self._lock:
            job = self._jobs.get(job_id)
            return bool(job) and job["status"] not in TERMINAL

    def get(self, job_id: str) -> Optional[dict]:
        self.expire_stuck()
        with self._lock:
            job = self._jobs.get(job_id)
            return dict(job) if job else None

    def list_done(self) -> list[dict]:
        with self._lock:
            done = [dict(j) for j in self._jobs.values() if j["status"] == "done"]
        return sorted(done, key=lambda j: j["created_at"], reverse=True)

    def delete(self, job_id: str) -> bool:
        with self._lock:
            if job_id not in self._jobs:
                return False
            del self._jobs[job_id]
            self._save()
            return True

    def expire_stuck(self) -> None:
        now = time.time()
        with self._lock:
            for j in self._jobs.values():
                if j["status"] not in TERMINAL and now - j["created_at"] > JOB_TIMEOUT_S:
                    msg = f"Timed out after {int(JOB_TIMEOUT_S // 60)} minutes (last step: {j['message']}). Please try again."
                    j.update(status="error", finished_at=now, error=msg, message=msg)
                    log.error("job %s timed out", j["id"])
                    self._save()

    @staticmethod
    def elapsed(job: dict) -> float:
        end = job["finished_at"] or time.time()
        return round(end - job["created_at"], 1)
