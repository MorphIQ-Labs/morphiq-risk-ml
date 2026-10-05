#!/usr/bin/env python3
"""Optional experiment collection. Standard library except reference generation."""
import argparse
import collections
import gzip
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import random
import re
import statistics
import struct
import subprocess
import sys
import time

NAMES = ['batch-fast', 'prepared-ocaml', 'native-scalar', 'native-simd', 'sleef-simd']
RUN_TIMEOUT_SECONDS = 180

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write(path, obj):
    Path(path).write_text(json.dumps(obj, indent=2, allow_nan=False) + '\n')

def word(x):
    return struct.pack('>d', x).hex()

def number(x):
    return struct.unpack('>d', bytes.fromhex(x))[0]

def generate(out, binary):
    import mpmath as mp
    assert mp.__version__ == '1.3.0'
    lines = []
    sources = {}
    for name in ['european', 'displaced']:
        p = Path('oracle/fixtures') / (name + '.txt.gz')
        sources[str(p)] = sha(p)
        lines += [s for s in gzip.decompress(p.read_bytes()).decode().splitlines() if s and not s.startswith('#')]
    original = len(lines)
    rng = random.Random(20261005)
    unresolved = []
    def add(f,k,t,r,sigma,side,family):
        def value(dps):
            with mp.workdps(dps):
                f0,k0,t0,r0,v0=map(mp.mpf,(f,k,t,r,sigma))
                distance=(f0-k0)*(1 if side=='call' else -1)
                scale=v0*mp.sqrt(t0)
                if scale == 0: p=max(distance,mp.mpf(0))
                else:
                    z=distance/scale
                    p=distance*mp.erfc(-z/mp.sqrt(2))/2+scale*mp.exp(-z*z/2)/mp.sqrt(2*mp.pi)
                return float(mp.exp(-r0*t0)*p)
        a,b=value(100),value(200)
        if word(a)!=word(b) or not math.isfinite(b):
            unresolved.append([f,k,t,r,sigma,side,family]);return
        fields=['bachelier',side,'otm' if (f-k)*(1 if side=='call' else -1)<=0 else 'itm',family]
        fields += [word(x) for x in (f,k,t,r,0.,sigma,0.,b)]
        lines.append(' '.join(fields))
    # Threshold neighbors, both sides, nonzero low words, broad ordinary scales.
    for side in ['call','put']:
        sign=1 if side=='call' else -1
        for q in [0., math.nextafter(.46875,0.), .46875, math.nextafter(.46875,math.inf), .5, 1., 2., math.nextafter(4.,0.),4.,math.nextafter(4.,math.inf),5.,12.,38.]:
            for exponent in [-101,-100,-20,0,20,99,100,101]:
                sigma=math.ldexp(1.,exponent)
                add(-sign*q*sigma,0.,1.,0.,sigma,side,'simd-boundaries')
    # Both the outer split exponent and inner exp argument reduction boundaries.
    ln2=float.fromhex('0x1.62e42fefa39efp-1')
    for n in range(1,12):
        for offset in [0., .5]:
            q=math.sqrt(2*(n+offset)*ln2)
            for z in [math.nextafter(q,0.),q,math.nextafter(q,math.inf)]:
                add(-z,0.,1.,0.,1.,'call','simd-reduction')
    for _ in range(2048):
        sigma=math.ldexp(rng.uniform(.5,1.),rng.randint(-90,90))
        t=rng.choice([.125,.25,.75,1.,1.5,3.])
        r=rng.uniform(-.1,.1)
        q=rng.uniform(.4,4.1)
        side=rng.choice(['call','put']); sign=1 if side=='call' else -1
        k=math.ldexp(rng.uniform(-1.,1.),rng.randint(-90,90))
        f=k-sign*q*sigma*math.sqrt(t)
        add(f,k,t,r,sigma,side,'simd-random')
    # Independent Bachelier references for every request used in timing.
    timed=subprocess.check_output([str(Path(binary).resolve()),'--dump-inputs'],text=True).splitlines()
    assert len(timed)==3*4096
    for line in timed:
        fields=line.split()
        if fields[0]=='bachelier':
            f,k,t,r,_,sigma,_,_=map(number,fields[4:])
            add(f,k,t,r,sigma,fields[1],fields[3])
    # Expected invalid/numerical failures are checked by exact baseline outcome.
    for f,k,t,r in [(1.,0.,-1.,0.),(1.,0.,1.,math.inf),(math.nan,0.,1.,0.),(sys.float_info.max,-sys.float_info.max,0.,0.),(1.,0.,1.,1e300),(1.,0.,1.,-1e300)]:
        lines.append(' '.join(['bachelier','call','boundary','simd-failure']+[word(x) for x in (f,k,t,r,0.,1.,0.,math.nan)]))
    Path(out).write_text('\n'.join(lines)+'\n')
    write(str(out)+'.json', {'source_fixtures':sources,'original_rows':original,'total_rows':len(lines),'mpmath':mp.__version__,'refinement_digits':[100,200],'unresolved':unresolved,'sha256':sha(out)})
    if unresolved: raise RuntimeError('Unresolved synthetic references retained; generation incomplete')
    print('Generated',len(lines),'rows')

def score(source, raw, destination):
    lines=Path(source).read_text().splitlines()
    rows=[json.loads(s) for s in Path(raw).read_text().splitlines()]
    assert len(rows)==len(lines), 'missing rows'
    stats=[dict(rows=0,changed=0,max_ulp=0,max_normwise=0.,gate_failures=0,exact_mismatches=0) for _ in NAMES]
    changes=[]; eligible=0; fallback_failures=0; regions={}
    for index,(line,row) in enumerate(zip(lines,rows)):
        assert row['row']==index and type(row['eligible']) is bool
        values=row['outcomes']; assert len(values)==5 and all(isinstance(v,str) for v in values)
        assert all(re.fullmatch('[0-9a-f]{16}',v) or v=='numerical_failure' or v.startswith('invalid:') for v in values)
        selected=row['eligible']; eligible+=selected
        fields=line.split(); ref=fields[-1]
        if not selected:
            assert all(v==values[0] for v in values), ('fallback mismatch',index)
            fallback_failures+=not bool(re.fullmatch('[0-9a-f]{16}',values[0]))
        else:
            assert fields[0]=='bachelier'
            assert all(re.fullmatch('[0-9a-f]{16}',v) and math.isfinite(number(v)) and number(v)>=0 for v in values)
            f,k,t,r,_,sigma,_,reference=map(number,fields[4:])
            assert math.isfinite(reference) and reference>=0
            scale=math.exp(-r*t)*(max(abs(f),abs(k))+sigma*math.sqrt(t)/math.sqrt(2*math.pi))
            key=fields[2]; region=regions.setdefault(key,[0]*5)
            for j,v in enumerate(values):
                s=stats[j];s['rows']+=1;s['changed']+=v!=values[0]
                ulp=abs(int(v,16)-int(ref,16))
                norm=abs(number(v)-reference)/(sys.float_info.epsilon*scale)
                s['max_ulp']=max(s['max_ulp'],ulp);region[j]=max(region[j],ulp)
                s['max_normwise']=max(s['max_normwise'],norm)
                s['gate_failures']+=ulp>8 or norm>4.3
                s['exact_mismatches']+=j<4 and v!=values[0]
            if any(v!=values[0] for v in values[1:]):
                changes.append(dict(row=index,input=line,outcomes=values,reference=ref))
    result={'total_rows':len(lines),'eligible':eligible,'fallback':len(lines)-eligible,'fallback_failures':fallback_failures,'backends':dict(zip(NAMES,stats)),'regional_max_ulp':regions,'changed_rows':changes,'input_sha256':sha(source),'trace_sha256':sha(raw),'operation_preserving_pass':all(s['exact_mismatches']==0 for s in stats[:4]),'sleef_quality_pass':stats[-1]['gate_failures']==0,'sleef_no_regional_regression':all(r[-1]<=r[0] for r in regions.values()),'universal_bound':False}
    write(destination,result)
    print(json.dumps({k:v for k,v in result.items() if k!='changed_rows'},indent=2))
    assert result['operation_preserving_pass'], 'operation-preserving mismatch'

def metadata(binary):
    git=lambda *args: subprocess.check_output(['git',*args],text=True).strip()
    assert not git('status','--porcelain','--untracked-files=all','--','lib'), 'changed library source'
    return {'source':git('rev-parse','HEAD'),'library_tree':git('rev-parse','HEAD:lib'),'source_status':git('status','--porcelain'), 'experiment_files':{str(p):sha(p) for p in sorted(Path('experiments/fast_simd').iterdir()) if p.is_file()}, 'platform':platform.platform(),'python':sys.version,'load':os.getloadavg(),'binary_sha256':sha(binary),'utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime())}

def adjudicate(report, destination):
    """Refine each changed price from original binary64 inputs, not intermediates."""
    import mpmath as mp
    assert mp.__version__ == '1.3.0'
    source=json.loads(Path(report).read_text()); rows=[]; counts=collections.Counter()
    for row in source['changed_rows']:
        fields=row['input'].split()
        assert fields[0]=='bachelier'
        inputs=list(map(number,fields[4:]))
        values=[number(row['outcomes'][j]) for j in [0,4]]
        refined=[]
        for digits in [100,200]:
            with mp.workdps(digits):
                f,k,t,r,_,sigma,_,reference=map(mp.mpf,inputs)
                distance=(f-k)*(1 if fields[1]=='call' else -1)
                s=sigma*mp.sqrt(t); z=distance/s
                exact=mp.exp(-r*t)*(distance*mp.erfc(-z/mp.sqrt(2))/2+s*mp.exp(-z*z/2)/mp.sqrt(2*mp.pi))
                assert word(float(exact))==row['reference'], ('reference changed',row['row'])
                errors=[(mp.mpf(v)-exact)/mp.mpf(math.ulp(inputs[-1])) for v in values]
                disposition='improved' if abs(errors[1])<abs(errors[0]) else 'worsened' if abs(errors[1])>abs(errors[0]) else 'equal'
                refined.append({'reference_decimal':mp.nstr(exact,60),'baseline_error_ulp':float(errors[0]),'sleef_error_ulp':float(errors[1]),'disposition':disposition})
        assert refined[0]==refined[1], ('unresolved changed row',row['row'])
        counts[refined[1]['disposition']]+=1
        rows.append(row|refined[1])
    write(destination,{'input_sha256':source['input_sha256'],'trace_sha256':source['trace_sha256'],'refinement_digits':[100,200],'counts':dict(counts),'rows':rows,'universal_bound':False})
    print(json.dumps(dict(counts)))

def collect(binary,out):
    out=Path(out);out.mkdir(exist_ok=False)
    before=metadata(binary);write(out/'before.json',before)
    all_rows=[]
    for run in range(4):
        start=metadata(binary)
        cmd=[str(Path(binary).resolve()),'--bench']+(['--reverse'] if run in [1,2] else [])
        with (out/f'run-{run}.jsonl').open('w') as stdout, (out/f'run-{run}.stderr').open('w') as stderr:
            subprocess.run(cmd,stdout=stdout,stderr=stderr,check=True,timeout=RUN_TIMEOUT_SECONDS)
        rows=[json.loads(s) for s in (out/f'run-{run}.jsonl').read_text().splitlines()]
        expected={(family,n,backend,phase,sample) for family in ['eligible','fallback-heavy','mixed'] for n in [1,32,256,4096] for backend in NAMES for phase in ['compile','execute','one-shot'] for sample in range(1,6)}
        seen=set()
        for r in rows:
            key=(r['family'],r['n'],r['backend'],r['phase'],r['sample'])
            assert r['kind']=='timing' and key in expected and key not in seen
            seen.add(key)
            assert all(math.isfinite(r[k]) and r[k]>=0 for k in ['ns','cpu_ns','bytes'])
            assert 0<=r['eligible']<=r['n'] and r['iterations']>=1
            r['run']=run
        assert seen==expected
        write(out/f'run-{run}-host.json',{'start':start,'end':metadata(binary)})
        all_rows+=rows
    after=metadata(binary);write(out/'after.json',after)
    assert all(before[k]==after[k] for k in ['binary_sha256','source','source_status','experiment_files'])
    grouped=collections.defaultdict(lambda:collections.defaultdict(list))
    for r in all_rows: grouped[(r['family'],r['n'],r['backend'],r['phase'])][r['run']].append(r)
    summary=[]
    for key,runs in grouped.items():
        medians=[statistics.median(r['ns'] for r in rs) for rs in runs.values()]
        summary.append(dict(zip(['family','n','backend','phase'],key))|{'median_process_median_ns':statistics.median(medians),'process_medians_ns':medians,'bytes':statistics.median(r['bytes'] for rs in runs.values() for r in rs),'eligible':next(iter(runs.values()))[0]['eligible']})
    write(out/'summary.json',{'complete':True,'samples':len(all_rows),'summary':summary})
    print('Collected',len(all_rows),'samples')

def main():
    p=argparse.ArgumentParser(description=__doc__)
    sub=p.add_subparsers(dest='command',required=True)
    g=sub.add_parser('generate');g.add_argument('output');g.add_argument('binary')
    s=sub.add_parser('score');s.add_argument('input');s.add_argument('trace');s.add_argument('output')
    c=sub.add_parser('collect');c.add_argument('binary');c.add_argument('output')
    d=sub.add_parser('adjudicate');d.add_argument('report');d.add_argument('output')
    a=p.parse_args()
    if a.command=='generate': generate(a.output, a.binary)
    elif a.command=='score': score(a.input,a.trace,a.output)
    elif a.command=='adjudicate': adjudicate(a.report,a.output)
    else: collect(a.binary,a.output)
if __name__=='__main__': main()
