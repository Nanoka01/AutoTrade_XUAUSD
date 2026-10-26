import numpy as np, pandas as pd
import engine as e

def atr(b, n=14):
    pc = b.close.shift()
    tr = pd.concat([b.high - b.low, (b.high - pc).abs(), (b.low - pc).abs()], axis=1).max(axis=1)
    return tr.ewm(alpha=1/n, adjust=False).mean()

def ema(s, n): return s.ewm(span=n, adjust=False).mean()

_cache = {}
def B(tf):
    if tf not in _cache:
        b = e.bars(tf); b['atr'] = atr(b); _cache[tf] = b
    return _cache[tf]

def close_time(b, tf):
    return b.index + pd.Timedelta(tf)

def donchian(tf='15min', n=20, trend=200, slk=2.0, tp=2.0, be=0.0, hours=(9, 22), maxh=24, dbias=0):
    b = B(tf).copy()
    hh = b.high.rolling(n).max().shift(); ll = b.low.rolling(n).min().shift()
    tr = ema(b.close, trend)
    up = (b.close > hh) & (b.close > tr); dn = (b.close < ll) & (b.close < tr)
    ct = close_time(b, tf)
    h = ct.hour
    ok = (h >= hours[0]) & (h < hours[1])
    if dbias > 0:
        db = daily_bias(ct, dbias)
        up &= db > 0; dn &= db < 0
    sig = (up | dn) & ok
    s = b[sig]
    return e.run(ct[sig], np.where(up[sig], 1, -1), slk * s.atr.values, tp, be, maxh * 60)

def orb(start=1, end=9, last_entry=17, slmode='range', slk=1.0, tp=2.0, be=0.0, maxh=12, minw=0.0, trend=0):
    """Asian range breakout: range of [start,end) server hours, first M5 close beyond it until last_entry."""
    b = B('5min').copy()
    d = b.index.normalize(); h = b.index.hour
    rng = b[(h >= start) & (h < end)].groupby(d[(h >= start) & (h < end)]).agg(hi=('high', 'max'), lo=('low', 'min'))
    b['hi'] = d.map(rng.hi); b['lo'] = d.map(rng.lo)
    win = (h >= end) & (h < last_entry)
    up = win & (b.close > b.hi); dn = win & (b.close < b.lo)
    if trend:
        dd = B('1D'); de = ema(dd.close, trend).shift()  # yesterday's EMA vs yesterday's close
        dc = dd.close.shift()
        bias = np.sign(dc - de).reindex(d).values
        up &= bias > 0; dn &= bias < 0
    first = (up | dn).groupby(d).cumsum() == 1
    sig = (up | dn) & first
    s = b[sig]
    width = (s.hi - s.lo).values
    sl = width * slk if slmode == 'range' else s.atr.values * slk
    keep = width >= minw * s.atr.values
    ct = close_time(b, '5min')[sig]
    return e.run(ct[keep], np.where(up[sig], 1, -1)[keep], sl[keep], tp, be, maxh * 60)

def pullback(tf='1h', fast=50, slow=200, entry_ema=20, slk=2.0, tp=2.0, be=0.0, hours=(0, 24), maxh=48, dbias=0):
    b = B(tf).copy()
    f = ema(b.close, fast); s_ = ema(b.close, slow); en = ema(b.close, entry_ema)
    upt = (f > s_) & (b.close > s_); dnt = (f < s_) & (b.close < s_)
    touched_dn = (b.low.shift() <= en.shift()); touched_up = (b.high.shift() >= en.shift())
    up = upt & touched_dn & (b.close > en) & (b.close > b.high.shift())
    dn = dnt & touched_up & (b.close < en) & (b.close < b.low.shift())
    ct = close_time(b, tf); h = ct.hour
    ok = (h >= hours[0]) & (h < hours[1])
    if dbias > 0:
        db = daily_bias(ct, dbias)
        up &= db > 0; dn &= db < 0
    sig = (up | dn) & ok
    s = b[sig]
    return e.run(ct[sig], np.where(up[sig], 1, -1), slk * s.atr.values, tp, be, maxh * 60)

def daily_bias(index_close_times, n):
    """+1/-1 from yesterday's daily close vs its EMA(n); aligned to signal times."""
    if n <= 0:
        return np.ones(len(index_close_times))
    dd = B('1D'); bias = np.sign(dd.close - ema(dd.close, n))
    bias.index = bias.index + pd.Timedelta('1D')     # known only after the day closes
    return bias.reindex(pd.DatetimeIndex(index_close_times), method='ffill').fillna(0).values

def gen(fam, dbias=0, **p):
    """Run a family with an optional daily-trend filter: trade only in the daily trend direction."""
    f = {'donch': donchian, 'pb': pullback, 'orb': orb}[fam]
    t = f(**p)
    return t
