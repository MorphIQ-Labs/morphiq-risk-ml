#!/usr/bin/env python3
"""Frozen exchange qualification cases, independent payoff bounds and scoring."""
import argparse
from fractions import Fraction
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys
import tempfile
import exchange_reference as initial
ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT/'docs/evidence/exchange-qualification'


def cases():
    rows = initial.cases()['rows']
    def add(id, p):
        rows.append(dict(id=id, required=False, inputs={k: initial.bits(p[k]) for k in initial.FIELDS}))
    base=dict(s1=100.,s2=95.,q1=.01,q2=.02,sigma1=.2,sigma2=.3,rho=.5,time=1.,limit=1e-9)
    for rho in (-1.,0.,.5,math.nextafter(1.,0.),1.):
        for ratio in (.01,1.,100.):
            for q1,q2 in ((0.,0.),(.01,.02),(-.125,.125)):
                for sigma1,sigma2 in ((0.,.3),(.2,.2),(.2,.3)):
                    for time in (.5,2.):
                        p=base|dict(s1=100.*ratio,s2=100.,q1=q1,q2=q2,sigma1=sigma1,sigma2=sigma2,rho=rho,time=time)
                        id=f'grid-{len(rows):04d}'
                        add(id,p)
                        add(id+'-reverse',p|dict(s1=p['s2'],s2=p['s1'],q1=q2,q2=q1,sigma1=sigma2,sigma2=sigma1))
    for exponent in (-1000,-500,0,500,1000):
        for rho in (-1.,0.,math.nextafter(1.,0.),1.):
            p=base|dict(s1=math.ldexp(1.,exponent),s2=math.ldexp(.95,exponent),rho=rho,
                       limit=math.ldexp(1e-9,exponent))
            add(f'scale-{exponent}-{rho.hex()}',p)
    for sigma in (math.ulp(0.),math.ldexp(1.,-537),1.,40.,80.,1e150):
        for rho in (-1.,0.,1.):
            add(f'extreme-{len(rows):04d}',base|dict(sigma1=sigma,sigma2=sigma,rho=rho,q1=0.,q2=0.))
    for q in (math.nextafter(256.,0.),256.,math.nextafter(256.,math.inf),-256.,math.nextafter(-256.,-math.inf)):
        add(f'discount-{len(rows):04d}',base|dict(q1=q,q2=q))
    return dict(schema=1, rows=rows, precision_bits=initial.PRECISIONS,
                quadrature=initial.QUADRATURE, worker_seconds=60, maximum_rows=10000)


def reference(row):
    from flint import arb, ctx
    p={k:initial.value(x) for k,x in row['inputs'].items()}
    if (not all(math.isfinite(x) for x in p.values()) or
        any(p[k]<0 for k in ('s1','s2','sigma1','sigma2','time','limit')) or abs(p['rho'])>1):
        return initial.reference(row)
    f={k:Fraction(x) for k,x in p.items()}
    v=f['time']*((f['sigma1']-f['sigma2'])**2+2*f['sigma1']*f['sigma2']*(1-f['rho']))
    if v < 6400 or p['s1']==0 or p['s2']==0:
        return initial.reference(row)
    # Independent payoff bound: a-C=E[min(X,b)], X=a exp(-v/2+sZ).
    # Split at Z=40; s>=80 implies both tilted and untilted tails <=Phi(-40).
    # Hence 0<=a-C<=(a+b)*exp(-800)/(40*sqrt(2*pi)). No CDF subtraction here.
    attempts=[]
    for precision in initial.PRECISIONS:
        ctx.prec=precision
        ball=lambda x: arb(x.numerator)/arb(x.denominator)
        a=ball(f['s1'])*(-ball(f['q1'])*ball(f['time'])).exp()
        b=ball(f['s2'])*(-ball(f['q2'])*ball(f['time'])).exp()
        s=ball(v).sqrt()
        ratio=(ball(f['s1'])/ball(f['s2'])).log()+(ball(f['q2'])-ball(f['q1']))*ball(f['time'])
        d1=ratio/s+s/2;d2=d1-s
        phi=lambda z: (-z/arb(2).sqrt()).erfc()/2
        closed=a*phi(d1)-b*phi(d2)
        deficit=(a+b)*arb(-800).exp()/(40*(2*arb.pi()).sqrt())
        bound=a+arb(0,deficit.upper())
        if not (closed.is_finite() and bound.is_finite()):
            attempts.append(dict(precision=precision,reason='nonfinite reference'));continue
        if not closed.overlaps(bound):
            return dict(status='route_disagreement',closed=closed.str(100,more=True),integral=bound.str(100,more=True))
        goal=min(a.abs_upper(),closed.abs_upper())*arb(2)**(-256)
        if closed.rad()<=goal and bound.rad()<=goal:
            return dict(status='interval',precision=precision,route='payoff-deficit-Mills-bound',
                        closed=closed.str(100,more=True),integral=bound.str(100,more=True))
        attempts.append(dict(precision=precision,reason='reference width'))
    return dict(status='unresolved',attempts=attempts)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--version',action='version',version='exchange-qualification 1')
    sub=parser.add_subparsers(dest='command',required=True)
    sub.add_parser('freeze')
    worker=sub.add_parser('worker');worker.add_argument('input',type=Path)
    run=sub.add_parser('reference');run.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    if args.command=='freeze':
        (BASE/'cases-v1.json').write_text(json.dumps(cases(),indent=2)+'\n')
    elif args.command=='worker':
        print(json.dumps(reference(json.loads(args.input.read_text()))))
    else:
        corpus=BASE/'cases-v1.json';rows=[]
        with tempfile.TemporaryDirectory() as tmp:
            path=Path(tmp)/'input.json'
            for row in json.loads(corpus.read_text())['rows']:
                path.write_text(json.dumps(row))
                try:
                    process=subprocess.run([sys.executable,__file__,'worker',str(path)],capture_output=True,text=True,check=True,timeout=60)
                    ref=json.loads(process.stdout)
                except subprocess.TimeoutExpired:
                    ref=dict(status='unresolved',reason='worker timeout')
                except (subprocess.CalledProcessError,json.JSONDecodeError) as exc:
                    ref=dict(status='tool_error',reason=str(exc),stderr=getattr(exc,'stderr',''))
                rows.append(row|dict(reference=ref));print(row['id'],ref['status'],flush=True)
        import importlib.metadata,platform
        from flint import __FLINT_VERSION__
        sources=[Path(__file__),ROOT/'scripts/exchange_reference.py',corpus]
        result=dict(schema=1,rows=rows,source_sha256={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sources},
                    tools=dict(python=platform.python_version(),python_flint=importlib.metadata.version('python-flint'),flint=__FLINT_VERSION__))
        args.output.write_text(json.dumps(result,indent=2)+'\n')
if __name__=='__main__':main()
