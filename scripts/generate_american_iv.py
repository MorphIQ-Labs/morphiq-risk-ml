#!/usr/bin/env python3
"""Independent fixed-quote inverse references; runtime-free, optional research tool."""
import argparse,hashlib,json,math,platform,struct,subprocess
from fractions import Fraction as F
from pathlib import Path
from flint import arb,ctx,__version__,__FLINT_VERSION__
ROOT=Path(__file__).resolve().parents[1]
def rat(x):
 m,e=map(int,x.man_exp());return F(m)*F(2)**e
def a(x):
 x=F(x);return arb(x.numerator)/x.denominator
def value(p,sigma,strike=None):
 s,k,r,q,t=map(a,[p['s'],p['k'] if strike is None else strike,p['r'],p['q'],p['t']]);v=a(sigma)*t.sqrt()
 if not sigma:return (s*(-q*t).exp()-k*(-r*t).exp()).max(arb(0)) if p['side']=='call' else (k*(-r*t).exp()-s*(-q*t).exp()).max(arb(0))
 d1=((s/k).log()+(r-q)*t)/v+v/2;d2=d1-v;sign=1 if p['side']=='call' else -1
 cdf=lambda x:(-x/arb(2).sqrt()).erfc()/2
 return sign*(s*(-q*t).exp()*cdf(sign*d1)-k*(-r*t).exp()*cdf(sign*d2))
def inverse(p,quote,precision):
 with ctx.workprec(precision):
  lo,hi=F(.05),F(.6);strike=F(p['k'])+F(p.get('cash',0.))
  assert value(p,lo,strike)<a(quote) and value(p,hi,strike)>a(quote)
  for _ in range(120):
   mid=(lo+hi)/2;v=value(p,mid,strike)
   if v<a(quote):lo=mid
   elif v>a(quote):hi=mid
   else:raise ValueError('unresolved Arb midpoint')
  return lo,hi

def main():
 ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--output',type=Path,required=True);ap.add_argument('--runners',type=Path,required=True);ap.add_argument('--version',action='version',version='american-iv-references 1');args=ap.parse_args();out=args.output;out.mkdir(exist_ok=False,parents=True)
 rows=[]
 def add(id,style='american',side='call',s=100.,k=100.,r=.05,q=0.,t=1.,opens=0.,sigma=.2,cash=0.,route='arb',quote_shift=0.):
  rows.append(dict(id=id,style=style,side=side,s=s,k=k,r=r,q=q,t=t,opens=opens,sigma=sigma,cash=cash,route=route,quote_shift=quote_shift))
 for s in [80.,100.,120.]:
  for r in [0.,.05]:
   for style in ['american','bermudan']:add(f'call-{s:g}-{r:g}-{style}',style=style,s=s,r=r)
 for side in ['call','put']:
  for r in [-.05,.05]:
   for style in ['american','bermudan']:add(f'terminal-{side}-{r:g}-{style}',style=style,side=side,r=r,q=.02,opens=1.)
 add('short-call',t=1/64,sigma=.3)
 add('low-vega-call',s=140.,sigma=.15)
 for shift in [-.01,.01]:add('quote-down' if shift<0 else 'quote-up',quote_shift=shift)
 for style in ['american','bermudan']:add('cash-terminal-'+style,style=style,k=90.,r=.03,q=.01,opens=1.,cash=10.)
 add('american-put',side='put',q=.02,route='discrete')
 add('negative-rate-put',side='put',r=-.02,q=.03,route='discrete')
 add('delayed-put',side='put',q=.02,opens=.5,route='discrete')
 add('bermudan-put',side='put',style='bermudan',q=.02,opens=.25,route='discrete')
 def wire(p,n,x):
  word=lambda v:struct.pack('>d',v).hex()
  return ' '.join([p['style'],p['id'],p['side'],str(n),str(math.ceil(n*p['opens']/p['t'])),*[word(v) for v in [p['s'],p['k'],p['r'],p['q'],x,p['t'],p['opens']]]])+'\n'
 def run(tool,tag,text,price=False):
  (out/(tag+'.input')).write_text(text)
  with (out/(tag+'.stdout')).open('w') as so,(out/(tag+'.stderr')).open('w') as se:
   result=subprocess.run([str(args.runners/tool),*(['--price'] if price else [])],input=text,text=True,stdout=so,stderr=se,timeout=600)
  assert result.returncode==0
  cells=(out/(tag+'.stdout')).read_text().strip().split('\t');assert len(cells)==6 and cells[2]=='finite',cells
  return F(float.fromhex(cells[3])),F(float.fromhex(cells[4]))
 for p in rows:
  if p['route']=='arb':
   with ctx.workprec(512):quote=float(value(p,F(p['sigma']),F(p['k'])+F(p['cash'])))+p['quote_shift']
   ranges=[inverse(p,quote,prec) for prec in [256,512]]
   assert max(x[0] for x in ranges)<=min(x[1] for x in ranges)
   lo=min(x[0] for x in ranges);hi=max(x[1] for x in ranges)
   p['attempts']=[dict(bits=b,lower=str(x),upper=str(y)) for b,(x,y) in zip([256,512],ranges)];p['resolved']=True
  else:
   quote=float(run('lattice',p['id']+'-quote',wire(p,4096,p['sigma']),True)[0]);ranges=[]
   for tool,levels in [('lattice',[1024,2048,4096]),('quantlib',[256,512,1024])]:
    roots=[run(tool,p['id']+f'-{tool}-{n}',wire(p,n,quote)) for n in levels]
    centres=[(l+h)/2 for l,h in roots];width=4*max(abs(centres[2]-centres[1]),abs(centres[1]-centres[0]))+F(1,2**30)
    ranges.append((roots[-1][0]-width,roots[-1][1]+width))
   lo=min(x for x,y in ranges);hi=max(y for x,y in ranges)
   p['attempts']=[dict(engine=tool,lower=str(x),upper=str(y)) for tool,(x,y) in zip(['lattice','quantlib'],ranges)]
   p['resolved']=hi-lo<=F(.005)/4
  p['quote']=quote.hex();p['lower']=str(lo);p['upper']=str(hi)
  print(p['id'],p['resolved'],float(lo),float(hi),flush=True)
 with ctx.workprec(512):
  p=dict(s=100.,k=10.,r=0.,q=0.,t=1.,side='call');w=[]
  for sig in [0.,.5,8.]:
   v=a(10)-value(p,F(sig),100)+value(p,F(sig),110)
   w.append(dict(sigma=sig.hex(),lower=str(rat(v.lower())),upper=str(rat(v.upper()))))
  assert F(w[0]['lower'])>F(w[1]['upper']) and F(w[2]['lower'])>F(w[1]['upper'])
 (out/'references.json').write_text(json.dumps(dict(rows=rows,cash_put_counterexample=w,discrete_scope='Empirical grid-refined comparison intervals, not continuum proofs.'),indent=2)+'\n')
 sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
 sources=['scripts/generate_american_iv.py','scripts/american_iv_reference.cpp','scripts/american_lattice.cpp','scripts/american_runner_io.hpp']
 (out/'manifest.json').write_text(json.dumps(dict(python=platform.python_version(),python_flint=__version__,flint=__FLINT_VERSION__,sources={s:sha(ROOT/s) for s in sources},binaries={s:sha(args.runners/s) for s in ['lattice','quantlib']},files={p.name:sha(p) for p in sorted(out.iterdir()) if p.is_file()}),indent=2)+'\n')
if __name__=='__main__':main()
