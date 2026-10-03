#!/usr/bin/env python3
"""Optional scalar portfolio shadow campaign; see docs/shadow-campaign.md."""
import argparse
from collections import Counter, defaultdict
from fractions import Fraction as F
import gzip
import hashlib
import importlib.metadata
import json
import math
import os
from pathlib import Path
import platform
import resource
import statistics
import struct
import subprocess
import time
import QuantLib as ql
from flint import arb, ctx, __FLINT_VERSION__
from arb_reference_campaign import price, classify, positive_tail, classify_positive_tail
from arb_greek_audit import derivative
from arb_iv_audit import certify as certify_iv
from canonical_dataset import load_dataset

NAMES = ['price','delta','gamma','rho','theta','vega','vanna','volga','charm','veta','color']
LIMIT = 1e-10
MATERIAL = F(1,100)

def word(x): return struct.pack('>d',float(x)).hex()
def number(s): return struct.unpack('>d',bytes.fromhex(s))[0]
def sha(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def command(*args): return subprocess.check_output(args,text=True).strip()
def rounded_quote(model,side,inputs):
    for bits in [256,512,1024,2048,4096]:
        with ctx.workprec(bits):
            v=price(model,side,inputs)
            candidate=float(v)
            if classify(v,candidate)=='certified': return candidate
            tail=positive_tail(model,side,inputs)
            for x in [candidate,math.nextafter(candidate,math.inf),math.nextafter(candidate,-math.inf)]:
                if classify_positive_tail(tail,x)=='certified': return x
    raise ArithmeticError('unresolved independent quote')

def corpus():
    rows=[]
    def add(model,side,inputs,scenario,category='interior',quote=None):
        i=len(rows)
        if quote is None: quote=rounded_quote(model,side,inputs)
        rows.append(dict(id=f'p{i:04d}',model=model,side=side,inputs=list(map(word,inputs)),
                         quote=word(quote),limit=word(LIMIT),scenario=scenario,category=category,
                         quantity=([-10000,25000,-50000,100000][i%4]),currency='USD',factor=model+'-synthetic'))
    for model in ['bsm','black76','displaced','bachelier']:
        for t in [1/12,1.,5.]:
            for m in [.8,1.,1.2]:
                for side in ['call','put']:
                    for scenario,ds,dv,dt in [('base',1.,1.,1.),('down',.9,1.3,.5),('up',1.1,.8,1.5)]:
                        if model=='bachelier': s,k,sigma,shift=(m-1)*10,0.,8.,0.
                        elif model=='displaced': s,k,sigma,shift=m*100-110,-10.,.23,110.
                        else: s,k,sigma,shift=m*100,100.,.23,0.
                        s=(s+shift)*ds-shift if model=='displaced' else s*ds
                        add(model,side,[s,k,t*dt,.025,.01 if model=='bsm' else .025,sigma*dv,shift],scenario)
    for model in ['bsm','black76','displaced','bachelier']:
        for side in ['call','put']:
            add(model,side,[100.,100.,0.,.02,.02,.2,10.],'expiry','boundary')
            add(model,side,[100.,100.,1.,.02,.02,0.,10.],'zero-variance','boundary')
            add(model,side,[100.,101.,1/4096,2048.,2048.,.2,10.],'joint-carry','stress')
            add(model,side,[100.,101.,1.,2048.,2048.,.2,10.],'carry-limit','stress',0.)
            add(model,side,[100.,101.,-1.,.02,.02,.2,10.],'invalid-time','invalid',0.)
    add('displaced','call',[2.,1.,1.,0.,0.,0.,2.**64],'lost-shift','boundary')
    add('bsm','call',[math.nextafter(1.,math.inf),2.**-53,1.,0.,0.,1e-4,0.],'midpoint','stress')
    return rows

def wire(rows,repeats):
    return ''.join('\t'.join([f'{rep}:{r["id"]}',r['model'],r['side'],*r['inputs'],r['quote'],r['limit']])+'\n'
                   for rep in range(repeats) for r in rows)

def worker(binary,rows,repeats):
    start=time.monotonic()
    p=subprocess.Popen([str(binary.resolve())],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
    ready=p.stdout.readline()
    cold=time.monotonic()-start
    if ready!='READY\n': raise RuntimeError('worker failed to become ready: '+ready)
    out,err=p.communicate(wire(rows,repeats),timeout=1800)
    wall=time.monotonic()-start
    if p.returncode: raise RuntimeError(f'worker exit {p.returncode}: {err}')
    result={};latencies=defaultdict(list); stats=None
    for line in out.splitlines():
        f=line.split('\t')
        if f[0]=='STATS': stats=dict(elapsed=float(f[1]),cpu=float(f[2]),allocated_words=float(f[3]),minor_collections=int(f[4]),major_collections=int(f[5]),clock_probe_seconds=float(f[6]));continue
        rep,id=f[0].split(':');rep=int(rep)
        if f[1]=='latency': latencies[rep].append(float(f[2]));continue
        key=(rep,id)
        if f[1] in result.setdefault(key,{}): raise RuntimeError('duplicate result')
        result[key][f[1]]=f[2:]
    assert stats is not None and len(result)==len(rows)*repeats
    baseline={r['id']:result[(0,r['id'])] for r in rows}
    for rep in range(repeats):
        assert len(latencies[rep])==len(rows)
        for row in rows:
            observed=result[(rep,row['id'])]
            assert observed==baseline[row['id']],'nondeterministic replay'
            expected={'admission'} if observed['admission'][0]!='ok' else {'admission','iv',*NAMES}
            assert set(observed)==expected,'truncated row'
    stats.update(process_to_ready_seconds=cold,subprocess_seconds=wall,latency_seconds=dict(latencies))
    return baseline,stats

def mapped(row):
    s,k,t,r,q,sigma,shift=map(number,row['inputs'])
    forward=s*math.exp((r-q)*t) if row['model']=='bsm' else s
    discount=math.exp(-r*t);total=sigma*math.sqrt(t)
    if row['model']=='displaced': forward,k=forward+shift,k+shift
    if not all(map(math.isfinite,[forward,k,discount,total])) or discount<=0: raise ValueError('nonfinite/zero mapped input')
    return forward,k,discount,total

def mapped_model(row,converted):
    forward,k,discount,total=map(arb,converted)
    s,_,t,*_=map(arb,map(number,row['inputs']))
    rate=-discount.log()/t
    sigma=total/t.sqrt()
    if row['model']=='bsm':
        return 'bsm',[s,k,t,rate,rate-(forward/s).log()/t,sigma,arb(0)]
    model='bachelier' if row['model']=='bachelier' else 'black76'
    return model,[forward,k,t,rate,rate,sigma,arb(0)]

def comparator(row):
    inputs=list(map(number,row['inputs']));s,k,t,r,q,sigma,shift=inputs
    if t<0: return dict(status='excluded_invalid_time')
    try:
        f,k,d,total=mapped(row);normal=row['model']=='bachelier';side=ql.Option.Call if row['side']=='call' else ql.Option.Put
        pricefn=ql.bachelierBlackFormula if normal else ql.blackFormula
        value=pricefn(side,k,f,total,d)
        values={'price':value}
        if t>0 and sigma>0:
            c=(ql.BachelierCalculator if normal else ql.BlackCalculator)(ql.PlainVanillaPayoff(side,k),f,total,d)
            values.update(delta=c.delta(s) if row['model']=='bsm' else c.deltaForward(),
                          gamma=c.gamma(s) if row['model']=='bsm' else c.gammaForward(),vega=c.vega(t),
                          volga=c.volga(t),vanna=c.vanna(t) if normal else c.vanna(s if row['model']=='bsm' else f,t),
                          rho=c.rho(t) if row['model']=='bsm' else -t*value)
            # Forward theta uses fixed F; using its own F as spot removes the carry term.
            # Normal forward zero is excluded because the calculator divides by spot.
            if row['model']=='bsm' or f>0:
                values['theta']=c.theta(s if row['model']=='bsm' else f,t)/365
        iv={'status':'excluded_expiry'}
        if t>0:
            try:
                quote=number(row['quote'])
                root=(ql.bachelierBlackFormulaImpliedVol(side,k,f,t,quote,d) if normal else
                      ql.blackFormulaImpliedStdDev(side,k,f,quote,d,0.,ql.nullDouble(),1e-12,1000)/math.sqrt(t))
                iv=dict(status='value',word=word(root))
            except RuntimeError as e: iv=dict(status='error',reason=str(e))
        return dict(status='ok',mapped=list(map(word,[f,k,d,total])),values={n:word(v) for n,v in values.items()},iv=iv)
    except (ValueError,OverflowError,RuntimeError) as e: return dict(status='error',reason=str(e))

def iv_comparison(row,output,comp):
    if comp['status']!='ok' or comp['iv']['status']!='value': return None
    theirs=number(comp['iv']['word'])
    record=dict(comparator_root=comp['iv']['word'],production_outcome=output[0],
                contract='Comparator approximate inverse; no nearest-even guarantee assumed')
    if output[0]=='root': record['difference']=number(output[1])-theirs
    original=list(map(number,row['inputs']))
    if theirs>0 and math.isfinite(theirs) and original[2]>0:
        with ctx.workprec(512):
            original[5]=theirs
            model,converted=mapped_model(row,list(map(number,comp['mapped'])))
            converted[5]=arb(theirs)
            record['original_model_quote_residual']=str(price(row['model'],row['side'],original)-arb(number(row['quote'])))
            record['mapped_model_quote_residual']=str(price(model,row['side'],converted)-arb(number(row['quote'])))
    return record

def exact_zero(row,name):
    s,k,t,r,q,sigma,shift=map(number,row['inputs'])
    # Symmetry of the normal price at F=K; no interval overlap counted as proof.
    return row['model']=='bachelier' and s==k and (name in ('vanna','volga') or (name=='charm' and r==0))

def validate(row,name,output):
    if output[0]!='ok': return dict(status='not_served',outcome=output[0])
    value,bound=map(number,output[1:]);assert math.isfinite(value) and 0<=bound<=number(row['limit'])
    inputs=list(map(number,row['inputs']))
    if bound==0 and value==0 and exact_zero(row,name): return dict(status='certified',method='normal-ATM-symmetry')
    for bits in [256,512,1024,2048,4096]:
        with ctx.workprec(bits):
            reference=price(row['model'],row['side'],inputs) if name=='price' else derivative(row['model'],row['side'],inputs,name)
            delta=abs(reference-arb(value))
            if delta<=arb(bound): return dict(status='certified',bits=bits)
            if delta>arb(bound): return dict(status='wrong',bits=bits,reference=str(reference),value=value,bound=bound)
    return dict(status='unresolved',reference=str(reference),value=value,bound=bound)

def comparison(row,name,output,comp):
    if output[0]!='ok' or comp['status']!='ok' or name not in comp['values']: return None
    original=list(map(number,row['inputs']));converted=list(map(number,comp['mapped']))
    ours=number(output[1]);theirs=number(comp['values'][name])
    with ctx.workprec(512):
        real=price(row['model'],row['side'],original) if name=='price' else derivative(row['model'],row['side'],original,name)
        if original[2]==0:
            # All models use original unshifted expiry payoff; shifted conversion can lose it.
            f,k,d,total=map(arb,converted);theta=1 if row['side']=='call' else -1
            x=theta*(f-k);mapped_real=d*(x+abs(x))/2
        else:
            model,inputs=mapped_model(row,converted)
            mapped_real=price(model,row['side'],inputs) if name=='price' else derivative(model,row['side'],inputs,name)
        material=abs(F(ours)-F(theirs))*abs(row['quantity'])>MATERIAL if name=='price' else abs(F(ours)-F(theirs))>F(LIMIT)
        record=dict(difference=ours-theirs,material=material,conversion=str(mapped_real-real),comparator_error=str(arb(theirs)-mapped_real))
        if material:
            if abs(mapped_real-real)>abs(arb(theirs)-mapped_real): disposition='input_conversion'
            elif name=='volga' and abs(arb(theirs)-mapped_real/arb(original[2]).sqrt())<arb(LIMIT):
                disposition='canonical_volga_missing_sqrt_maturity'
                record['source_formula_residual']=str(arb(theirs)-mapped_real/arb(original[2]).sqrt())
            elif name=='vanna' and row['model']=='bachelier' and abs(arb(theirs)-mapped_real/arb(converted[2]))<arb(LIMIT):
                disposition='canonical_normal_vanna_missing_discount'
                record['source_formula_residual']=str(arb(theirs)-mapped_real/arb(converted[2]))
            else: disposition='requires_review'
            record['disposition']=disposition
        return record

def iv_outcome(row,output):
    status=output[0];inputs=list(map(number,row['inputs']));quote=number(row['quote'])
    if status=='root' and number(output[1])>0:
        bits=certify_iv(row['model'],row['side'],[*inputs,quote],number(output[1]))
        return dict(status='certified_positive_root' if bits else 'unresolved',bits=bits)
    if status=='expiry':
        return dict(status='certified_expiry' if inputs[2]==0 else 'wrong')
    if status not in ('root','below_intrinsic','above_maximum'):
        return dict(status=status)
    for bits in [256,512,1024,2048,4096]:
        with ctx.workprec(bits):
            s,k,t,r,y,_,shift=map(arb,inputs)
            if row['model']=='displaced': s,k=s+shift,k+shift
            if row['model']!='bsm': y=r
            theta=1 if row['side']=='call' else -1
            spread=theta*(s-k)*(-r*t).exp() if row['model']!='bsm' or inputs[3]==inputs[4] else theta*(s*(-y*t).exp()-k*(-r*t).exp())
            intrinsic=arb(0) if spread<=0 else spread if spread>0 else (spread+abs(spread))/2
            q=arb(quote)
            if status=='root':
                if number(output[1])!=0: return dict(status='wrong')
                if q==intrinsic or (q<intrinsic and classify(intrinsic,quote)=='certified'):
                    return dict(status='certified_zero_root',bits=bits)
            elif status=='below_intrinsic' and q<intrinsic and classify(intrinsic,quote)=='wrong':
                return dict(status='certified_below_intrinsic',bits=bits)
            elif status=='above_maximum' and row['model']!='bachelier':
                s,k,t,r,y,_,shift=map(arb,inputs)
                if row['model']=='displaced': s,k=s+shift,k+shift
                if row['model']!='bsm': y=r
                maximum=s*(-y*t).exp() if row['side']=='call' else k*(-r*t).exp()
                if q>=maximum: return dict(status='certified_above_maximum',bits=bits)
    return dict(status='unresolved',outcome=status)

def outward(x):
    f=float(x)
    return math.nextafter(f,math.inf) if F(f)<x else f

def aggregates(rows,results,comparators):
    groups=defaultdict(list)
    for row in rows:
        for name in NAMES:
            key=(row['scenario'],row['model'],row['factor'],name,row['currency'])
            groups[key].append((row,results[row['id']].get(name,['not_admitted'])))
    reports=[]
    for key,items in sorted(groups.items()):
        failures=[r['id'] for r,o in items if o[0]!='ok']
        record=dict(group=key,count=len(items),complete=not failures,failed_ids=failures)
        if not failures:
            center=sum((F(r['quantity'])*F(number(o[1])) for r,o in items),F())
            radius=sum((abs(r['quantity'])*F(number(o[2])) for r,o in items),F())
            value=float(center);bound=outward(radius+abs(F(value)-center))
            record.update(value_word=word(value),absolute_error_word=word(bound),gross_value=float(sum(abs(F(r['quantity'])*F(number(o[1]))) for r,o in items)))
        canonical=[]
        for r,o in items:
            c=comparators[r['id']]
            if c['status']=='ok' and key[3] in c['values']:
                canonical.append((r,number(c['values'][key[3]])))
        record['comparator_complete']=len(canonical)==len(items)
        if not failures and record['comparator_complete']:
            total=sum((F(r['quantity'])*F(v) for r,v in canonical),F())
            gross=sum((abs(F(r['quantity'])*(F(number(o[1]))-F(v))) for (r,o),(_,v) in zip(items,canonical)),F())
            record.update(comparator_total_word=word(float(total)),difference=float(center-total),gross_difference=float(gross),
                          material_price=key[3]=='price' and (abs(center-total)>MATERIAL or gross>MATERIAL))
        reports.append(record)
    return reports

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--worker',type=Path,default=Path('_build/default/bench/shadow.exe'))
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--input',type=Path,help='Captured canonical portfolio (JSON or gzip); quotes are preserved')
    parser.add_argument('--runs',type=int,default=3)
    parser.add_argument('--repeats',type=int,default=3)
    args=parser.parse_args()
    if args.runs<1 or args.repeats<1: parser.error('positive runs/repeats required')
    assert ql.__version__=='1.43' and importlib.metadata.version('python-flint')=='0.9.0'
    dataset,rows=load_dataset(args.input) if args.input else (None,corpus())
    load0=os.getloadavg();runs=[];reference=None
    for run in range(args.runs):
        result,stats=worker(args.worker,rows,args.repeats)
        if reference is None: reference=result
        else: assert result==reference,'fresh-process replay differs'
        runs.append(stats);print('worker',run,stats['elapsed'],flush=True)
    records=[];counts=Counter();findings=[];bad=[];comparators={}
    for row in rows:
        result=reference[row['id']];comp=comparator(row);comparators[row['id']]=comp;audits={};comparisons={}
        for name in NAMES:
            output=result.get(name,['not_admitted'])
            audit=validate(row,name,output);audits[name]=audit
            counts[row['category']+'/'+name+'/'+audit['status']]+=1
            if audit['status'] in ('wrong','unresolved') or (row['category']=='interior' and audit['status']!='certified'): bad.append(dict(id=row['id'],name=name,audit=audit))
            compared=comparison(row,name,output,comp)
            if compared:
                comparisons[name]=compared
                if compared['material']: findings.append(dict(id=row['id'],name=name,**compared))
        iv=result.get('iv',['not_admitted']);iva=iv_outcome(row,iv)
        if iva['status'] in ('wrong','unresolved'): bad.append(dict(id=row['id'],name='iv',audit=iva))
        counts[row['category']+'/iv/'+iva['status']]+=1
        if row['category']=='interior' and iva['status']!='certified_positive_root': bad.append(dict(id=row['id'],name='iv',audit=iva))
        records.append(dict(input=row,outputs=result,audits=audits,iv_audit=iva,comparator=comp,iv_comparison=iv_comparison(row,iv,comp),comparisons=comparisons))
    # A completed independent rejection, not a crash or an absent reference.
    control_row=rows[0];correct=reference[control_row['id']]['price']
    corrupt=['ok',word(number(correct[1])+1.),correct[2]]
    if validate(control_row,'price',corrupt)['status']!='wrong': raise AssertionError('wrong output escaped')
    corrupted=reference.copy();corrupted[control_row['id']]=dict(reference[control_row['id']],price=['numerical_failure'])
    control_groups=aggregates(rows,corrupted,comparators)
    target=next(g for g in control_groups if g['group']==(control_row['scenario'],control_row['model'],control_row['factor'],'price','USD'))
    if target['complete'] or 'value_word' in target: raise AssertionError('partial aggregate exposed as complete')
    if any(f['disposition']=='requires_review' for f in findings): bad.append(dict(unresolved_material_comparator_findings=True))
    sources=[Path(__file__),Path('bench/shadow.ml'),Path('bench/dune'),Path('bench/assurance_clock.c'),Path('docs/shadow-campaign.md'),Path('scripts/arb_reference_campaign.py'),Path('scripts/arb_greek_audit.py'),Path('scripts/arb_iv_audit.py')]+list(Path('lib').rglob('*.ml'))+list(Path('lib').rglob('*.mli'))+list(Path('lib').rglob('*.c'))
    report=dict(specification='docs/shadow-campaign.md',source_parent=command('git','rev-parse','HEAD'),source_sha256={str(p):sha(p) for p in sources},worker_sha256=sha(args.worker),
                versions=dict(quantlib=ql.__version__,python_flint=importlib.metadata.version('python-flint'),flint=__FLINT_VERSION__,python=platform.python_version(),
                              ocaml=command('opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-version'),flambda=command('opam','exec','--switch=morphiq-risk-ml','--','ocamlopt','-config-var','flambda')),
                platform=platform.platform(),cpu=command('sysctl','-n','machdep.cpu.brand_string') if platform.system()=='Darwin' else platform.processor(),
                load_before=load0,load_after=os.getloadavg(),process_runs=runs,
                peak_child_rss_bytes=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss*(1 if platform.system()=='Darwin' else 1024),
                rss_scope='Maximum across worker and metadata subprocesses in this dedicated harness process, not incremental allocation or GC pause time.',
                counts=counts,rows=records,aggregates=aggregates(rows,reference,comparators),findings=findings,failed_audits=bad,
                deterministic_repetitions=args.runs*args.repeats,wrong_value_rejected=True,incomplete_aggregate_rejected=True,
                scope='Synthetic diagnostic, not institutional portfolio representativeness or approval. Comparator discrepancies remain visible; no default CI dependency.')
    if dataset is not None:
        report.update(specification=dataset['specification'],
                      input_artifact=dict(path=str(args.input),sha256=sha(args.input),rows_sha256=dataset['rows_sha256']),
                      input_provenance={k:v for k,v in dataset.items() if k!='rows'},
                      scope='Owner-authorized generated canonical scalar workload; no claim of observed institutional portfolio coverage or a latency SLA.')
        for path in ['scripts/canonical_dataset.py','docs/canonical-dataset.md']:
            report['source_sha256'][path]=sha(path)
    encoded=(json.dumps(report,indent=2,allow_nan=False)+'\n').encode()
    if args.output.suffix=='.gz':
        with args.output.open('wb') as stream:
            with gzip.GzipFile(fileobj=stream,mode='wb',mtime=0,filename='') as z: z.write(encoded)
    else: args.output.write_bytes(encoded)
    print(json.dumps(dict(rows=len(rows),counts=counts,material_findings=len(findings),failed_audits=len(bad))))
    if bad: raise SystemExit(1)

if __name__=='__main__': main()
