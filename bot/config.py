"""Settings loaded from the .env file next to this script."""
from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from dotenv import load_dotenv

HERE = Path(__file__).resolve().parent
load_dotenv(HERE / ".env")


def _default_common_dir() -> Path:
    # MT5 shared folder used by FILE_COMMON: %APPDATA%\MetaQuotes\Terminal\Common\Files
    appdata = os.environ.get("APPDATA", str(Path.home()))
    return Path(appdata) / "MetaQuotes" / "Terminal" / "Common" / "Files"


def _int(name: str, default: int | None = None) -> int:
    raw = os.environ.get(name, "").strip()
    if not raw:
        if default is None:
            raise SystemExit(f"Missing {name} in .env")
        return default
    return int(raw)


@dataclass(frozen=True)
class Config:
    token: str
    guild_id: int
    owner_id: int
    channel_control: int
    channel_trades: int
    channel_alerts: int
    channel_reports: int
    bridge_dir: Path
    heartbeat_timeout: int
    report_hour: int
    timezone: str
    healthcheck_url: str
    db_path: Path


def load() -> Config:
    token = os.environ.get("DISCORD_TOKEN", "").strip()
    if not token:
        raise SystemExit("Missing DISCORD_TOKEN in .env")
    common = Path(os.environ.get("MT5_COMMON_DIR", "").strip() or _default_common_dir())
    return Config(
        token=token,
        guild_id=_int("GUILD_ID"),
        owner_id=_int("OWNER_ID"),
        channel_control=_int("CHANNEL_CONTROL"),
        channel_trades=_int("CHANNEL_TRADES"),
        channel_alerts=_int("CHANNEL_ALERTS"),
        channel_reports=_int("CHANNEL_REPORTS"),
        bridge_dir=common / os.environ.get("BRIDGE_DIR", "XauScalper").strip(),
        heartbeat_timeout=_int("HEARTBEAT_TIMEOUT", 120),
        report_hour=_int("REPORT_HOUR", 23),
        timezone=os.environ.get("TIMEZONE", "Asia/Bangkok").strip(),
        healthcheck_url=os.environ.get("HEALTHCHECK_URL", "").strip(),
        db_path=HERE / "trades.db",
    )
