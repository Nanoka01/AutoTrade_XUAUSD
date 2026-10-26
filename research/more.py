import strats as S, engine as e, itertools, pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
rows=[]
for tf,n,slk,tp,db in itertools.product(['5min','10min'],[20,55,100],[2.0,3.0,4.0],[0,3.0],[100,200]):
    p=dict(tf=tf,n=n,trend=200,slk=slk,tp=tp,dbias=db,hours=(0,24),maxh=72 if tp==0 else 48)
    t=S.donchian(**p); i=t[t.time.dt.year<2026]; o=t[t.time.dt.year==2026]
    si=e.stats(i,risk=.0025); so=e.stats(o,risk=.0025)
    rows.append(dict(tf=tf,n=n,slk=slk,tp=tp,db=db,n_is_mo=round(len(i)/36,1),PF_is=si['PF'],minY=min(si['years'].values()),dd_is=si['maxDD%'],PF_oos=so['PF'],n_oos_mo=round(len(o)/10,1)))
d=pd.DataFrame(rows); pd.set_option('display.width',200)
print(d.sort_values('PF_is',ascending=False).to_string(index=False))
