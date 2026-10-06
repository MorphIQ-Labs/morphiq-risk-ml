#!/usr/bin/env python3
"""Independent exact-input terminal-cash call references (optional python-flint)."""
import argparse,hashlib,json,platform
from fractions import Fraction as F
from pathlib import Path
from flint import arb,ctx,__version__,__FLINT_VERSION__
def a(x):
 x=F(x);return arb(x.numerator)/x.denominator
def rat(x):
 n,e=map(int,x.man_exp());return F(n)*F(2)**e
def price(p):
 r=sum((a(v)*a(dt) for dt,v in p['rates']),arb(0))
 q=sum((a(v)*a(dt) for dt,v in p['yields']),arb(0))
 variance=sum((a(v)**2*a(dt) for dt,v in p['vols']),arb(0))
 k=F(p['k'])+(sum(map(F,p['cash']),F(0)) if p['phase']=='after' else 0)
 s=a(p['s']);ka=a(k);x=s*(-q).exp();y=ka*(-r).exp()
 if not k:return x
 if not p['s']:return arb(0)
 root=variance.sqrt();d1=((s/ka).log()+r-q)/root+root/2;d2=d1-root
 # erfc, independent of the runtime's series/continued-fraction CDF.
 cdf=lambda x:(-x/arb(2).sqrt()).erfc()/2
 return x*cdf(d1)-y*cdf(d2)
def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--version',action='version',version='terminal-cash-reference 1');args=ap.parse_args()
 rows=[]
 def add(id,s=100.,k=90.,r=.03,q=.01,v=.2,cash=(10.,),phase='after',piecewise=False):
  p=dict(id=id,s=s,k=k,cash=list(cash),phase=phase,piecewise=piecewise,rates=[(1.,r)],yields=[(1.,q)],vols=[(1.,v)])
  if piecewise:p.update(rates=[(.5,r),(.5,-.02)],yields=[(.25,q),(.75,.04)],vols=[(.75,v),(.25,.35)])
  intervals=[]
  for bits in [256,512]:
   with ctx.workprec(bits):
    x=price(p);intervals.append((rat(x.lower()),rat(x.upper())))
  assert max(lo for lo,hi in intervals)<=min(hi for lo,hi in intervals)
  p['lower']=str(min(lo for lo,hi in intervals));p['upper']=str(max(hi for lo,hi in intervals));p['precision_intervals']=[[str(lo),str(hi)] for lo,hi in intervals];rows.append(p)
 for s in [80.,100.,120.]:
  for r,q in [(.03,.01),(-.05,.02),(.02,-.03)]:
   for phase in ['before','after','both']:add(f'constant-{s:g}-{r:g}-{phase}',s=s,r=r,q=q,phase=phase)
 for phase in ['before','after','both']:
  add('joint-'+phase,cash=(4.,6.,2**-50),phase=phase)
  add('piecewise-'+phase,piecewise=True,phase=phase)
 add('low-word',s=1e16,k=1e16,r=0.,q=0.,v=1e-16,cash=(1.,))
 add('joint-low-words',s=1e16,k=1e16,r=0.,q=0.,v=1e-16,cash=(1.,2**-53,2**-106))
 add('zero-effective-strike',k=0.,cash=(0.,))
 add('zero-strike-cash',k=0.,cash=(100.,))
 add('tiny-scale',s=1e-100,k=9e-101,cash=(1e-101,))
 add('large-scale',s=1e100,k=9e99,cash=(1e99,))
 add('large-dividend',s=100.,k=10.,v=1.,cash=(200.,))
 args.output.mkdir(parents=True,exist_ok=False)
 data=dict(schema=1,python=platform.python_version(),python_flint=__version__,flint=__FLINT_VERSION__,generator_sha256=hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),bits=[256,512],rows=rows)
 (args.output/'references.json').write_text(json.dumps(data,indent=2)+'\n')
 with (args.output/'references.tsv').open('w') as f:
  for p in rows:
   vals=[p['id'],p['phase'],'piecewise' if p['piecewise'] else 'constant',*[float(p[k]).hex() for k in ['s','k']],*[float(p[k][0][1]).hex() for k in ['rates','yields','vols']],','.join(x.hex() for x in p['cash']),p['lower'],p['upper']]
   f.write(' '.join(vals)+'\n')
 print(len(rows),'independent cases; each will exercise American and Bermudan APIs')
if __name__=='__main__':main()
