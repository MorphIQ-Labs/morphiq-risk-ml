#!/usr/bin/env python3
"""Refine every timed Bachelier input from the public tile benchmark dump.

Gaussian-expectation formula at 100/200 digits, as in the retained #121
experiment. Identical original inputs reuse a reference; row multiplicity and
order are retained. This optional command requires mpmath 1.3.0.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import struct


def word(x):return struct.pack('>d',x).hex()
def number(x):return struct.unpack('>d',bytes.fromhex(x))[0]
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def generate(source,out):
    import mpmath as mp
    if mp.__version__!='1.3.0':raise ValueError('mpmath 1.3.0 required')
    cache={};lines=[];unresolved=[];total=0
    for line in source.read_text().splitlines():
        total+=1;fields=line.split()
        if len(fields)!=12:raise ValueError('malformed timed input')
        if fields[0]!='bachelier':continue
        if fields[1] not in ['call','put']:raise ValueError('invalid side')
        original=tuple([fields[1],*fields[4:11]])
        f,k,t,r,_,sigma,_=map(number,fields[4:11])
        if not all(math.isfinite(x) for x in [f,k,t,r,sigma]) or t<0 or sigma<0:
            raise ValueError('invalid reference input')
        if original not in cache:
            values=[]
            for precision in [100,200]:
                with mp.workdps(precision):
                    forward,strike,time,rate,vol=map(mp.mpf,[f,k,t,r,sigma])
                    distance=(forward-strike)*(1 if fields[1]=='call' else -1)
                    scale=vol*mp.sqrt(time)
                    if scale==0:price=max(distance,mp.mpf(0))
                    else:
                        z=distance/scale
                        price=distance*mp.erfc(-z/mp.sqrt(2))/2+scale*mp.exp(-z*z/2)/mp.sqrt(2*mp.pi)
                    values.append(float(mp.exp(-rate*time)*price))
            cache[original]=values
        a,b=cache[original]
        if word(a)!=word(b) or not math.isfinite(b):unresolved.append(dict(row=total,inputs=line,rounded=[word(a),word(b)]))
        region='otm' if (f-k)*(1 if fields[1]=='call' else -1)<=0 else 'itm'
        lines.append(' '.join([*fields[:2],region,fields[3],*fields[4:11],word(b)]))
    if not lines:raise ValueError('empty timed Bachelier corpus')
    out.write_text('\n'.join(lines)+'\n')
    report=dict(input_sha256=sha(source),output_sha256=sha(out),generator_sha256=sha(__file__),
        total_input_rows=total,bachelier_rows=len(lines),unique_original_inputs=len(cache),
        mpmath=mp.__version__,precision_digits=[100,200],unresolved=unresolved,
        method='Gaussian expectation from exact original binary64 inputs; precision agreement is empirical evidence, not proof')
    Path(str(out)+'.json').write_text(json.dumps(report,indent=2)+'\n')
    if unresolved:raise ValueError('unresolved original-input references retained')


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='native-tile-references-1')
    p.add_argument('input',type=Path);p.add_argument('output',type=Path)
    a=p.parse_args();generate(a.input,a.output)


if __name__=='__main__':main()
