# Strategy research (Python)

Backtests signals on M1 bars exported from MT5 by `MQL5/Scripts/XauScalper/ExportHistory.mq5`.

1. Run ExportHistory on an XAUUSD chart (set Tools > Options > Charts > Max bars to Unlimited first).
2. Convert the CSV to `m1.pkl` (pandas `read_csv`, index = time in seconds) and point `engine.py` at it.
3. `python oos.py` runs the grid: 2023-2025 is in-sample, 2026 is the out-of-sample check.

Needs `pandas`, `numpy`, `numba`.
