#!/usr/bin/env python3
"""Exact binary64 policy-matrix checks and strict optional-benchmark parsers."""
from fractions import Fraction as Q
import math
from pathlib import Path
import re
from measure_american_workloads import STATUS, number
HEX=re.compile(r'[a-f0-9]{64}\Z')

def finite(word):
    x=float.fromhex(word)
    if not math.isfinite(x):raise ValueError('nonfinite matrix/result')
    return x

def matrices(path):
    lines=Path(path).read_text().splitlines();result=[];i=0;keys=set()
    while i<len(lines):
        head=lines[i].split('\t');i+=1
        if len(head)!=4 or head[0]!='MATRIX':raise ValueError('matrix header')
        n,ordinal=int(head[1]),int(head[2]);allowance=finite(head[3])
        if not 2<=n<=8190 or ordinal not in (1,2,8,32,128,512) or (n,ordinal) in keys or allowance<0:
            raise ValueError('matrix identity/allowance')
        keys.add((n,ordinal));rows=[]
        for _ in range(n):
            if i==len(lines):raise ValueError('truncated matrix')
            f=lines[i].split('\t');i+=1
            if len(f)!=7 or f[0]!='DATA' or f[6] not in ('0','1'):raise ValueError('matrix row')
            rows.append([finite(v) for v in f[1:6]]+[int(f[6])])
        result.append(dict(n=n,ordinal=ordinal,allowance=allowance,rows=rows))
    return result

def exact(matrix,solution):
    n=matrix['n']
    if len(solution)!=n or not all(math.isfinite(x) for x in solution):raise ValueError('solution shape/nonfinite')
    x=list(map(Q.from_float,solution));margins=[];residual=Q(0)
    for i,row in enumerate(matrix['rows']):
        lo,d,hi,b=map(Q.from_float,row[:4])
        if lo>0 or hi>0 or d<=0 or (i==0 and lo!=0) or (i==n-1 and hi!=0):
            raise ValueError('not an effective M-matrix')
        margins.append(d+lo+hi)
        r=d*x[i]-b
        if i:r+=lo*x[i-1]
        if i+1<n:r+=hi*x[i+1]
        residual=max(residual,abs(r))
    margin=min(margins)
    if margin<=0:raise ValueError('nonpositive exact dominance margin')
    bound=residual/margin
    return dict(margin_exact=str(margin),residual_exact=str(residual),error_bound_exact=str(bound),
                residual=float(residual),error_bound=float(bound),allowance=matrix['allowance'],
                passes=residual<=Q.from_float(matrix['allowance']))

def micro(text,inputs,repeats=32):
    solutions={};samples={};complete=False
    for line in text.splitlines():
        f=line.split('\t')
        if f[0]=='SOLUTION' and len(f)>=4:
            index,n=int(f[1]),int(f[2])
            if index in solutions or not 0<=index<len(inputs) or n!=inputs[index]['n'] or len(f)!=n+4:
                raise ValueError('solution identity/shape')
            residual=finite(f[3])
            if residual<0:raise ValueError('negative residual')
            solutions[index]=dict(residual=residual,values=[finite(v) for v in f[4:]])
        elif f[0]=='MICRO' and len(f)==6:
            key=int(f[1]),int(f[2])
            if key in samples or int(f[3])!=repeats:raise ValueError('micro duplicate/repetitions')
            samples[key]=dict(preparation_s=number(f[4]),total_s=number(f[5],True))
        elif f[0]=='COMPLETE' and len(f)==2 and int(f[1])==len(inputs) and not complete:complete=True
        else:raise ValueError('unknown micro record')
    expected={(m['n'],b) for m in inputs for b in (1,8,64)}
    if not complete or len(solutions)!=len(inputs) or set(samples)!=expected:raise ValueError('incomplete micro evidence')
    return dict(solutions=solutions,samples={f'{n}/{b}':s for (n,b),s in samples.items()})

def requests(text,case,size,capture=False):
    expected_rows=1 if size==1 else 8
    expected_methods={'admission','scalar','batch','planner1'}|({'planner4'} if size==4 else set())
    rows={};values={};times={};memory={};compilation={};complete=False
    for line in text.splitlines():
        f=line.split('\t');tag=f[0]
        if tag=='ROW' and len(f)==4:
            i=int(f[1]);statuses=f[3].split(',')
            if i in rows or not 0<=i<expected_rows or not HEX.fullmatch(f[2]) or not set(statuses)<=STATUS:
                raise ValueError('request row identity/status')
            if len(statuses)!=(2 if case in ('greeks','curve-greeks') else 1):raise ValueError('request quantity count')
            rows[i]=dict(digest=f[2],statuses=statuses)
        elif tag=='VALUES' and len(f)==3:
            i=int(f[1])
            if i in values or not 0<=i<expected_rows:raise ValueError('duplicate/invalid values')
            values[i]=[finite(v) for v in f[2].split(',') if v]
        elif tag=='TIME' and len(f)==4:
            if f[1] in times or f[1] not in expected_methods:raise ValueError('time method')
            times[f[1]]=dict(wall_s=number(f[2]),first_s=number(f[3]))
        elif tag=='MEMORY' and len(f)==3:
            if f[1] in memory or f[1] not in expected_methods:raise ValueError('memory method')
            memory[f[1]]=number(f[2])
        elif tag=='COMPILE' and len(f)==3:
            if f[1] in compilation or f[1] not in ('batch','planner'):raise ValueError('compile method')
            compilation[f[1]]=number(f[2],True)
        elif tag=='COMPLETE' and f==['COMPLETE',case,str(size),str(expected_rows)] and not complete:complete=True
        else:raise ValueError('unknown request record')
    if len(rows)!=expected_rows or len(values)!=expected_rows:raise ValueError('incomplete request rows')
    if capture:
        if times or memory or compilation or complete:raise ValueError('unexpected capture measurement')
    elif not complete or set(times)!=expected_methods or set(memory)!=expected_methods or set(compilation)!={'batch','planner'}:
        raise ValueError('incomplete request matrix')
    return dict(rows=rows,values=values,times=times,memory=memory,compilation=compilation)
