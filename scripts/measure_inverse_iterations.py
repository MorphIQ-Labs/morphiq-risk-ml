#!/usr/bin/env python3
"""Count LBR and certified-IV work in an isolated, instrumented source copy.

The retained per-input trace includes outputs. Counters never enter the
production library or timed benchmarks. Builds use two jobs. A successful
ordinary oracle-IV run is required; this diagnostic is not a correctness proof.
"""
import argparse
import gzip
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def replace(path, old, new, count=1):
    source=path.read_text();assert source.count(old)==count,(path,old)
    path.write_text(source.replace(old,new))


def main(args):
    root=args.root.resolve()
    tracked=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
    with tempfile.TemporaryDirectory(prefix='inverse-iterations-') as temporary:
        dest=Path(temporary)
        for name in filter(None,tracked):
            target=dest/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(root/name,target)
        (dest/'lib/inverse_diagnostics.ml').write_text('''let lbr_calls = ref 0
let lbr_steps = ref 0
let certified_calls = ref 0
let certified_steps = ref 0
let finish_lbr n = incr lbr_calls; lbr_steps := !lbr_steps + n
let () = at_exit (fun () -> Printf.eprintf "COUNTS %d %d %d %d\\n" !lbr_calls !lbr_steps !certified_calls !certified_steps)
''')
        replace(dest/'lib/lbr.ml', 'if n >= iterations || not (Float.abs ds > epsilon_float *. s) then s',
                'if n >= iterations || not (Float.abs ds > epsilon_float *. s) then (Inverse_diagnostics.finish_lbr n; s)',3)
        replace(dest/'lib/certified_iv.ml','    let steps = ref 0 in','    let () = incr Inverse_diagnostics.certified_calls in\n    let steps = ref 0 in')
        replace(dest/'lib/certified_iv.ml','      incr steps','      incr Inverse_diagnostics.certified_steps; incr steps')
        # The public result is printed immediately after the solve, before scoring.
        replace(dest/'test/oracle_iv.ml','             let key =', '             Printf.eprintf "RESULT %s\\t%s\\n" line (show got);\n             let key =')
        build=subprocess.run(['opam','exec','--switch=morphiq-risk-ml','--','dune','build','-j','2','test/oracle_iv.exe','oracle/fixtures/iv.txt'],cwd=dest,text=True,capture_output=True)
        assert build.returncode==0,build.stdout+build.stderr
        run=subprocess.run([str(dest/'_build/default/test/oracle_iv.exe'),str(dest/'_build/default/oracle/fixtures/iv.txt')],cwd=dest,text=True,capture_output=True)
        assert run.returncode==0,run.stdout+run.stderr
        counters=[s for s in run.stderr.splitlines() if s.startswith('COUNTS ')]
        assert len(counters)==1,counters
        trace=[s.removeprefix('RESULT ') for s in run.stderr.splitlines() if s.startswith('RESULT ')]
        assert trace
        data=dict(source_head=subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True).strip(),
                  source_sha256={name:hashlib.sha256((root/name).read_bytes()).hexdigest() for name in ('lib/normal.ml','lib/normal_dd.ml','lib/dd.ml','lib/lbr.ml','lib/certified_iv.ml','test/oracle_iv.ml')},
                  counts=dict(zip(('lbr_iterated_calls','lbr_steps','certified_calls','certified_steps'),map(int,counters[0].split()[1:]))),
                  rows=len(trace),trace=trace,oracle_log=run.stdout)
        args.output.write_bytes(gzip.compress((json.dumps(data,indent=2)+'\n').encode(),mtime=0))
        print(json.dumps({k:v for k,v in data.items() if k not in ('trace','oracle_log')},indent=2))


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='measure_inverse_iterations 1')
    p.add_argument('--root',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
    main(p.parse_args())
