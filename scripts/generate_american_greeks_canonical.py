"""Supplementary exact-Time QuantLib derivative/parallel-bump/valuation-roll comparison."""
import argparse
import hashlib
import json
from pathlib import Path
import time
from generate_american_greeks import BASE, families, sources
from american_piecewise_reference import protocol
from american_reference_data import capture, require


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='american-greeks-canonical 1')
    p.add_argument('--executable',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    rows=json.loads((BASE/'cases-v1.json').read_text())['rows'];family,excluded=families(rows);allrows=rows+family
    manifest=dict(sources=sources(),binary_sha256=hashlib.sha256(a.executable.read_bytes()).hexdigest(),runs=[],complete=False)
    (a.output/'families.json').write_text(json.dumps(dict(rows=family,excluded=excluded),indent=2)+'\n')
    for n in (128,256,512):
        outputs=[]
        for batch,start in enumerate(range(0,len(allrows),256)):
            data=''.join(protocol(r,n)+'\n' for r in allrows[start:start+256]);name=f'canonical-family-{n}-{batch}';(a.output/(name+'.input')).write_text(data)
            begin=time.time()
            try:outputs.append(capture([str(a.executable.resolve())],data,a.output/(name+'.tsv'),1800))
            finally:
                manifest['runs'].append(dict(n=n,batch=batch,seconds=time.time()-begin))
                (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        (a.output/f'canonical-family-{n}.tsv').write_text(''.join(outputs))
        print(n,'complete',flush=True)
    require(manifest['sources']==sources(),'canonical reference source drift')
    require(manifest['binary_sha256']==hashlib.sha256(a.executable.read_bytes()).hexdigest(),'canonical binary drift')
    manifest['complete']=True;(a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')

if __name__=='__main__':main()
