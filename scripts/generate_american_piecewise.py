"""Run the frozen independent campaign with prebuilt optional research dependencies."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys
import time
from american_piecewise_reference import protocol


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='piecewise-generate 1')
    p.add_argument('--quadrature',type=Path,required=True)
    p.add_argument('--quantlib',type=Path,required=True)
    p.add_argument('--mpmath-python',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    a=p.parse_args();a.output.mkdir(parents=True,exist_ok=False)
    sha=lambda f:hashlib.sha256(f.read_bytes()).hexdigest()
    scripts=Path(__file__).resolve().parent;root=scripts.parent
    cases=root/'docs/evidence/american-piecewise/cases-v1.json'
    sources=[cases,*scripts.glob('american_piecewise*'),Path(__file__),scripts/'collect_american_piecewise.py',scripts/'american_runner_io.hpp',scripts/'american_cash_io.hpp',scripts/'bermudan_io.hpp']
    guard={str(f.relative_to(root)):sha(f) for f in sources if f.is_file()}
    manifest=dict(started=time.time(),sources=guard,runs=[])
    rows=json.loads(cases.read_text())['rows']
    def run(command, name, data=''):
        begin=time.time()
        dest=a.output/name
        (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        try:r=subprocess.run(command,input=data,text=True,capture_output=True,timeout=1800,cwd=root)
        except (OSError,subprocess.TimeoutExpired) as e:
            (a.output/(name+'.failure')).write_text(str(e));raise
        dest.write_text(r.stdout);(a.output/(name+'.stderr')).write_text(r.stderr)
        manifest['runs'].append(dict(command=command,name=name,returncode=r.returncode,seconds=time.time()-begin,stdout_sha256=sha(dest)))
        (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
        if r.returncode:raise RuntimeError('reference process failed: '+name)
    manifest['binaries']={str(f.resolve()):sha(f) for f in (a.quadrature,a.quantlib)}
    for name,exe,ns in [('quantlib',a.quantlib,[128,256,512]),('quadrature',a.quadrature,[8,256,512,1024])]:
        for n in ns:
            data=''.join(protocol(row,n)+'\n' for row in rows)
            (a.output/f'input-{n}.txt').write_text(data)
            run([str(exe.resolve())],f'{name}-{n}.tsv',data)
    version=subprocess.check_output([str(a.mpmath_python.absolute()),'-c','import mpmath;print(mpmath.__version__)'],text=True).strip()
    if version!='1.3.0':raise RuntimeError('mpmath version differs from protocol')
    manifest['mpmath']=version
    for precision in (80,160):
        for label,script in [('analytic','american_piecewise_reference.py'),('discrete','american_piecewise_discrete.py')]:
            run([str(a.mpmath_python.absolute()),str(scripts/script),'--precision',str(precision)],f'{label}-{precision}.jsonl')
    if guard!={str(f.relative_to(root)):sha(f) for f in sources if f.is_file()}:raise RuntimeError('reference sources changed during collection')
    manifest['complete']=True
    (a.output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    print('complete independent campaign:',a.output)

if __name__=='__main__':main()
