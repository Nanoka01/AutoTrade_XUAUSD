"""File bridge to the EA. Mirrors MQL5/Include/XauScalper/Bridge.mqh."""
from __future__ import annotations

import json
import time
import uuid
from pathlib import Path


class Bridge:
    def __init__(self, base: Path):
        self.base = base
        self.events_dir = base / "events"
        self.commands_dir = base / "commands"
        self.status_path = base / "status.json"
        self.events_dir.mkdir(parents=True, exist_ok=True)
        self.commands_dir.mkdir(parents=True, exist_ok=True)

    def read_status(self) -> dict | None:
        try:
            return json.loads(self.status_path.read_text(encoding="utf-8-sig"))
        except (FileNotFoundError, json.JSONDecodeError, PermissionError):
            return None

    def status_age(self, status: dict | None) -> float | None:
        """Seconds since the EA last wrote its status, or None when there is no status yet."""
        if not status or "ts" not in status:
            return None
        return max(0.0, time.time() - float(status["ts"]))

    def pop_events(self) -> list[dict]:
        """Returns new events oldest first and deletes their files."""
        events = []
        for path in sorted(self.events_dir.glob("*.json"), key=_event_sort_key):
            try:
                events.append(json.loads(path.read_text(encoding="utf-8-sig")))
            except json.JSONDecodeError:
                pass  # files are renamed into place complete, so this is a corrupt file: drop it
            except (PermissionError, FileNotFoundError):
                continue  # EA still holds it; try again next round
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        return events

    def send_command(self, cmd: str, arg: str = "") -> str:
        cmd_id = uuid.uuid4().hex[:10]
        tmp = self.commands_dir / f"{cmd_id}.tmp"
        tmp.write_text(f"id={cmd_id}\ncmd={cmd}\narg={arg}\n", encoding="utf-8")
        tmp.replace(self.commands_dir / f"{cmd_id}.cmd")
        return cmd_id


def _event_sort_key(path: Path) -> tuple[int, int]:
    # evt_<tickcount>_<counter>.json
    parts = path.stem.split("_")
    try:
        return int(parts[1]), int(parts[2])
    except (IndexError, ValueError):
        return 0, 0
