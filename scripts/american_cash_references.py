#!/usr/bin/env python3
"""Frozen cash references. Optional research tool; stdlib + pinned mpmath."""
import argparse, datetime, hashlib, json, math, pathlib, struct, subprocess
import mpmath as mp

FIELDS=('spot','strike','rate','yield_','volatility','time','opens')
def decode(x): return struct.unpack('>d',bytes.fromhex(x))[0]
def wire(row,n):
    return ' '.join([row['id'],row['side'],str(n),'0',*[row['inputs'][k] for k in FIELDS],*[str(row[k]) for k in ('valuation_side','opening_side','expiry_side')],str(len(row['cash'])),*[v for e in row['cash'] for v in (e['time'],e['amount'])]])
def exact(x):
    a,b=decode(x).as_integer_ratio(); return mp.mpf(a)/b

def analytical(row,dps):
    with mp.workdps(dps):
        s,k,r,q,v,t,opens=[exact(row['inputs'][key]) for key in FIELDS]
        cash={}
        for e in row['cash']:
            time=exact(e['time']); cash[time]=cash.get(time,mp.mpf(0))+exact(e['amount'])
        side=row['side']; before,opening,expiry=[row[key] for key in ('valuation_side','opening_side','expiry_side')]
        def payoff(x):return max(x-k if side=='call' else k-x,mp.mpf(0))
        def eligible(time,phase):return (time>opens or (time==opens and phase>=opening)) and (time<t or (time==t and phase<=expiry))
        if s==0:return mp.nstr(0 if side=='call' else k*mp.exp(-r*(t if r<0 else opens)),dps)
        if k==0 and side=='put':return '0'
        if v==0 or t==0:
            best=mp.mpf(0); stock=s; previous=mp.mpf(0)
            for time in sorted(set([mp.mpf(0),opens,t,*cash])):
                if time>previous:
                    lo=max(previous,opens); hi=time
                    def at(z):return mp.exp(-r*z)*payoff(stock*mp.exp((r-q)*(z-previous)))
                    if lo<=hi:
                        best=max(best,at(lo),at(hi))
                        if r*q>0 and r!=q and stock>0 and k>0:
                            root=previous+mp.log(r*k/(q*stock))/(r-q)
                            if lo<root<hi:best=max(best,at(root))
                    stock*=mp.exp((r-q)*(time-previous))
                if time in cash and not(time==t and expiry==1) and not(time==0 and before==2):
                    if eligible(time,1):best=max(best,mp.exp(-r*time)*payoff(stock))
                    stock=max(stock-cash[time],mp.mpf(0))
                    if eligible(time,2):best=max(best,mp.exp(-r*time)*payoff(stock))
                elif eligible(time,expiry if time==t else before if time==0 else 0):best=max(best,mp.exp(-r*time)*payoff(stock))
                previous=time
            return mp.nstr(best,dps)
        def call(spot,strike):
            if spot==0:return mp.mpf(0)
            if strike==0:return spot*mp.exp(-q*t)
            z=(mp.log(spot/strike)+(r-q+v*v/2)*t)/(v*mp.sqrt(t)); cdf=lambda x:mp.erfc(-x/mp.sqrt(2))/2
            return spot*mp.exp(-q*t)*cdf(z)-strike*mp.exp(-r*t)*cdf(z-v*mp.sqrt(t))
        if opens==t and list(cash)==[t]:
            d=0 if expiry==1 else cash[t]
            value=call(s,k+d) if side=='call' else k*mp.exp(-r*t)-call(s,d)+call(s,k+d)
            return mp.nstr(value,dps)
        if list(cash)==[0] and side=='call' and q==0 and r>=0 and opening==2:
            return mp.nstr(call(s if before==2 else max(s-cash[0],0),k),dps)
        return None

def main():
    ap=argparse.ArgumentParser(description=__doc__);ap.add_argument('--version',action='version',version='american-cash-references 1')
    ap.add_argument('--quadrature',required=True);ap.add_argument('--quantlib',required=True);ap.add_argument('--output',type=pathlib.Path,required=True)
    args=ap.parse_args(); args.output.mkdir(parents=True,exist_ok=True)
    corpus=json.loads(pathlib.Path('docs/evidence/american-cash/cases-v1.json').read_text())
    report={'schema':1,'created_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'runtime_changed':False,'rows':[],'runners':{}}
    parsed={}
    for name,exe,levels in [('quadrature',args.quadrature,(256,512,1024)),('quantlib',args.quantlib,(128,256,512))]:
        request=''.join(wire(row,n)+'\n' for row in corpus['rows'] for n in levels)
        (args.output/(name+'-input.txt')).write_text(request)
        result=subprocess.run([exe],input=request,text=True,capture_output=True,timeout=900)
        (args.output/(name+'.tsv')).write_text(result.stdout);(args.output/(name+'.stderr')).write_text(result.stderr)
        if result.returncode:raise RuntimeError(name+' failed: '+result.stderr)
        lines=[line.split('\t') for line in result.stdout.splitlines()]
        if len(lines)!=len(corpus['rows'])*3:raise RuntimeError('truncated runner output')
        data={}
        for row in corpus['rows']:
            data[row['id']]=[]
            for n in levels:
                fields=lines.pop(0)
                if fields[:2]!=[row['id'],str(n)]:raise RuntimeError('runner ordering')
                data[row['id']].append(fields)
        parsed[name]=data
        report['runners'][name]={'binary_sha256':hashlib.sha256(pathlib.Path(exe).read_bytes()).hexdigest(),'levels':levels}
    for row in corpus['rows']:
        out={'id':row['id'],'analytical_80':analytical(row,80),'analytical_160':analytical(row,160),'quadrature':parsed['quadrature'][row['id']],'quantlib':parsed['quantlib'][row['id']]}
        if out['analytical_160'] is not None:
            # Precision agreement is supplementary, not a certified interval.
            with mp.workdps(180):
                a,b=mp.mpf(out['analytical_80']),mp.mpf(out['analytical_160']);value=float(b); radius=float(abs(a-b)+abs(mp.mpf(value)-b)+mp.mpf('1e-75')*max(1,abs(b)))
            out.update(value=value,radius=radius,reference_kind='precision-refined-analytical')
        elif all(f[2]=='finite' for f in out['quadrature']):
            pairs=[(float.fromhex(f[3]),float.fromhex(f[4])) for f in out['quadrature']];values=[a+(b-a)/2 for a,b in pairs]
            radius=4*max(abs(values[1]-values[0]),abs(values[2]-values[1]))+(pairs[-1][1]-pairs[-1][0])/2+256*2**-53*1024*max(decode(row['inputs']['spot']),decode(row['inputs']['strike']))
            out.update(value=values[-1],radius=radius,reference_kind='empirical-quadrature')
        if 'radius' in out:
            out['primary_resolved']=2*out['radius']<=decode(row['epsilon'])/8
            out['loose_resolved']=2*out['radius']<=max(decode(row['inputs']['spot']),decode(row['inputs']['strike']))/800
        report['rows'].append(out)
    paths=['scripts/freeze_american_cash.py','scripts/american_cash_io.hpp','scripts/american_runner_io.hpp','scripts/american_cash_quadrature.cpp','scripts/american_cash_quantlib.cpp',__file__,'docs/evidence/american-cash/cases-v1.json','docs/evidence/american-cash/protocol.md']
    report['source_sha256']={p:hashlib.sha256(pathlib.Path(p).read_bytes()).hexdigest() for p in paths}
    report['raw_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in args.output.glob('*.tsv')}
    (args.output/'references.json').write_text(json.dumps(report,indent=2,allow_nan=False)+'\n')
if __name__=='__main__':main()
