import strats as S, engine as e, pandas as pd, numpy as np, warnings, itertools; warnings.filterwarnings('ignore')
base=dict(trend=200,tp=0,dbias=200,hours=(0,24),maxh=72)
subs={'A_M15n55':S.donchian(tf='15min',n=55,slk=3.0,**base),
      'B_H1n20':S.donchian(tf='1h',n=20,slk=3.0,**base),
      'C_M30n20':S.donchian(tf='30min',n=20,slk=3.0,**base),
      'D_M10n55':S.donchian(tf='10min',n=55,slk=4.0,**base),
      'E_M5n100':S.donchian(tf='5min',n=100,slk=4.0,**base),
      'F_ORB':S.orb(start=1,end=8,last_entry=20,slmode='range',slk=1.0,tp=3.0,trend=50)}
def port(keys, risk):
    t=pd.concat([subs[k].assign(s=k) for k in keys]).sort_values('exit_time')
    out={}
    for lab,m in [('IS',t.time.dt.year<2026),('2026',t.time.dt.year==2026)]:
        x=t[m]; eq=np.cumprod(1+risk*x.r.values); pk=np.maximum.accumulate(eq); dd=((pk-eq)/pk).max()*100
        pos=x.r[x.r>0].sum(); neg=-x.r[x.r<0].sum()
        months=36 if lab=='IS' else 10
        out[lab]=dict(perMo=round(len(x)/months,1),PF=round(pos/neg,2),ret=round((eq[-1]-1)*100,1),retYr=round(((eq[-1])**(12/months)-1)*100,1),dd=round(dd,1))
    return out
# correlation of monthly R
mr=pd.DataFrame({k:v.groupby(v.exit_time.dt.to_period('M')).r.sum() for k,v in subs.items()}).fillna(0)
print(mr[mr.index.year<2026].corr().round(2))
for k in subs: print(k, port([k],0.0025))
for keys in [['A_M15n55','B_H1n20'],['A_M15n55','C_M30n20'],['A_M15n55','B_H1n20','C_M30n20'],['A_M15n55','B_H1n20','F_ORB'],['A_M15n55','B_H1n20','C_M30n20','F_ORB'],['A_M15n55','D_M10n55','B_H1n20','F_ORB']]:
    for r in [0.0015,0.002,0.0025]:
        print(keys, r*100, port(keys,r))
