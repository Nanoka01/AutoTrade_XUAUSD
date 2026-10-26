"""Closed-trade log in SQLite, used for /report and the daily summary."""
from __future__ import annotations

import sqlite3
import time
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Summary:
    trades: int
    wins: int
    net: float
    gross_profit: float
    gross_loss: float
    best: float
    worst: float

    @property
    def win_rate(self) -> float:
        return self.wins / self.trades * 100 if self.trades else 0.0

    @property
    def profit_factor(self) -> float | None:
        return self.gross_profit / self.gross_loss if self.gross_loss else None


class TradeDb:
    def __init__(self, path: Path):
        self.conn = sqlite3.connect(path)
        self.conn.execute(
            """CREATE TABLE IF NOT EXISTS trades (
                   ticket INTEGER PRIMARY KEY,
                   closed_at REAL NOT NULL,
                   side TEXT, volume REAL, price REAL, profit REAL, reason TEXT, currency TEXT)"""
        )
        self.conn.commit()

    def add_close(self, event: dict) -> None:
        d = event.get("data", {})
        if "ticket" not in d:
            return
        self.conn.execute(
            "INSERT OR REPLACE INTO trades VALUES (?,?,?,?,?,?,?,?)",
            (
                int(d["ticket"]),
                float(event.get("ts", time.time())),
                d.get("side"),
                d.get("volume"),
                d.get("price"),
                float(d.get("profit", 0)),
                d.get("reason"),
                d.get("currency"),
            ),
        )
        self.conn.commit()

    def summary(self, since: float) -> Summary:
        rows = [r[0] for r in self.conn.execute("SELECT profit FROM trades WHERE closed_at >= ?", (since,))]
        wins = [p for p in rows if p > 0]
        losses = [p for p in rows if p < 0]
        return Summary(
            trades=len(rows),
            wins=len(wins),
            net=sum(rows),
            gross_profit=sum(wins),
            gross_loss=-sum(losses),
            best=max(rows, default=0.0),
            worst=min(rows, default=0.0),
        )
