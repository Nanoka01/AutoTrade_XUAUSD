"""Bar-close signals on a higher timeframe, executed and managed on M1 bars.
Prices in the data are bid; buys pay the spread on entry, sells on exit.
If SL and TP fall inside the same M1 bar, the SL is assumed to hit first."""
import numpy as np, pandas as pd
from numba import njit

M1 = pd.read_pickle('/home/claude/research/m1.pkl')
POINT = 0.01
MIN_SPREAD_FRAC = 8e-5   # ~0.36 USD at 4500: the live tester showed 30-50 point spreads

def spread_series(df):
    return np.maximum(df.spread.values * POINT, MIN_SPREAD_FRAC * df.close.values)

O = M1.open.values; H = M1.high.values; L = M1.low.values; C = M1.close.values
SP = spread_series(M1)
T = M1.index.values.astype('datetime64[m]').astype(np.int64)  # minutes
DOW = M1.index.dayofweek.values; HR = M1.index.hour.values

def bars(tf):
    r = M1.resample(tf, label='left', closed='left').agg(
        {'open': 'first', 'high': 'max', 'low': 'min', 'close': 'last', 'tick_volume': 'sum', 'spread': 'median'}).dropna()
    return r

@njit(cache=True)
def _sim(O, H, L, C, SP, T, DOW, HR, eidx, edir, esl, etp, ebe, emaxmin, fri_close):
    n = len(eidx)
    res_r = np.full(n, np.nan); res_exit = np.zeros(n, np.int64); res_kind = np.zeros(n, np.int64)
    busy_until = -1
    N = len(O)
    for k in range(n):
        i = eidx[k]
        if i <= busy_until or i >= N:
            continue
        d = edir[k]; sp = SP[i]
        entry = O[i] + sp if d == 1 else O[i]
        sl_dist = esl[k]
        sl = entry - d * sl_dist; tp = entry + d * etp[k] * sl_dist if etp[k] > 0 else np.nan
        be_done = False
        tmax = T[i] + emaxmin[k]
        j = i
        exit_px = np.nan; kind = 0
        while j < N:
            spj = SP[j]
            # bid-side extremes; for sells the ask = bid + spread
            if d == 1:
                lo = L[j]; hi = H[j]
                if lo <= sl:
                    exit_px = min(sl, O[j]) if j > i else sl; kind = 1; break
                if tp == tp and hi >= tp:
                    exit_px = max(tp, O[j]) if j > i else tp; kind = 2; break
                if ebe[k] > 0 and not be_done and hi - entry >= ebe[k] * sl_dist:
                    sl = entry + 0.0; be_done = True
            else:
                hi = H[j] + spj; lo = L[j] + spj
                if hi >= sl:
                    exit_px = max(sl, O[j] + spj) if j > i else sl; kind = 1; break
                if tp == tp and lo <= tp:
                    exit_px = min(tp, O[j] + spj) if j > i else tp; kind = 2; break
                if ebe[k] > 0 and not be_done and entry - lo >= ebe[k] * sl_dist:
                    sl = entry - 0.0; be_done = True
            if T[j] >= tmax or (fri_close >= 0 and DOW[j] == 4 and HR[j] >= fri_close):
                exit_px = C[j] if d == 1 else C[j] + spj; kind = 3; break
            # gap over a weekend/day: next bar far in time is fine, handled by O[j] checks
            j += 1
        if j >= N:
            break
        res_r[k] = d * (exit_px - entry) / sl_dist
        res_exit[k] = j; res_kind[k] = kind
        busy_until = j
    return res_r, res_exit, res_kind

def run(sig_time, direction, sl_dist, tp_r, be_r=0.0, max_min=24*60, fri_close=20):
    """sig_time: bar close timestamps; entry at first M1 bar at/after that time."""
    sig_time = pd.DatetimeIndex(sig_time)
    eidx = np.searchsorted(M1.index.values, sig_time.values)
    m = eidx < len(M1)
    n = m.sum()
    arr = lambda x: np.broadcast_to(np.asarray(x, dtype=float), (len(sig_time),))[m].copy()
    r, ex, kind = _sim(O, H, L, C, SP, T, DOW, HR, eidx[m].astype(np.int64), np.asarray(direction)[m].astype(np.int64),
                       arr(sl_dist), arr(tp_r), arr(be_r), arr(max_min).astype(np.int64), fri_close)
    ok = ~np.isnan(r)
    t = pd.DataFrame({'time': sig_time[m][ok], 'dir': np.asarray(direction)[m][ok], 'r': r[ok], 'kind': kind[ok],
                      'exit_time': M1.index.values[ex[ok]]})
    return t

def stats(t, risk=0.005, label=''):
    if len(t) == 0:
        return {'label': label, 'n': 0}
    r = t.r.values
    eq = np.cumprod(1 + risk * r); peak = np.maximum.accumulate(eq)
    dd = ((peak - eq) / peak).max() * 100
    pos = r[r > 0].sum(); neg = -r[r < 0].sum()
    yrs = t.groupby(t.time.dt.year).r.sum().round(1).to_dict()
    return {'label': label, 'n': len(r), 'win%': round((r > 0).mean() * 100, 1), 'avgR': round(r.mean(), 3),
            'PF': round(pos / neg, 2) if neg > 0 else np.inf, 'totR': round(r.sum(), 1),
            'ret%': round((eq[-1] - 1) * 100, 1), 'maxDD%': round(dd, 1), 'years': yrs}
