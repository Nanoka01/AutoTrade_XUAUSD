import strats as S, engine as e, itertools, pandas as pd, numpy as np, warnings; warnings.filterwarnings('ignore')
rows=[]
def add(name, params, t):
    i=t[t.time.dt.year<2026]; o=t[t.time.dt.year==2026]
    si=e.stats(i); so=e.stats(o)
    rows.append({'fam':name, **{k:str(v) for k,v in params.items()}, 'PF_is':si['PF'],'minY':min(si['years'].values()),
                 'n_oos':so['n'],'PF_oos':so.get('PF'),'R_oos':so.get('totR'),'dd_oos':so.get('maxDD%'),
                 'RL_oos':round(o[o.dir==1].r.sum(),1),'RS_oos':round(o[o.dir==-1].r.sum(),1)})
for tf,n,slk,tp,db in itertools.product(['15min','30min','1h'],[20,55],[1.5,3.0],[2.0,3.0,0],[0,50,100,200]):
    p=dict(tf=tf,n=n,trend=200,slk=slk,tp=tp,dbias=db,hours=(0,24),maxh=72 if tp==0 else 48); add('donch',p,S.donchian(**p))
for tf,en,slk,tp,db in itertools.product(['15min','30min','1h'],[10,20],[1.5,2.5],[2.0,3.0,4.0],[0,50,100,200]):
    p=dict(tf=tf,fast=50,slow=200,entry_ema=en,slk=slk,tp=tp,dbias=db); add('pb',p,S.pullback(**p))
df=pd.DataFrame(rows); df.to_pickle('oos.pkl')
pd.set_option('display.width',250)
print(df.groupby(['fam','dbias']).agg(cfgs=('PF_oos','size'),is_PF=('PF_is','median'),oos_PF_med=('PF_oos','median'),
      share_oos_PF_gt1=('PF_oos',lambda s:(s>1).mean()),R_oos_med=('R_oos','median'),RL=('RL_oos','median'),RS=('RS_oos','median')).round(2))
