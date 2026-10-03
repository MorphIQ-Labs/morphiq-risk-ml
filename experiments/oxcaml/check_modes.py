#!/usr/bin/env python3
"""Compile real OxCaml ownership violations and matching local-state controls."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

CASES={
 'mutable_global': ('let shared = ref 0\nlet worker = Domain.Safe.spawn (fun () -> incr shared)\n',
                    'let worker = Domain.Safe.spawn (fun () -> let shared = ref 0 in incr shared)\n'),
 'shared_cache': ('let cache = Hashtbl.create 4\nlet worker = Domain.Safe.spawn (fun () -> Hashtbl.replace cache 1 2)\n',
                  'let worker = Domain.Safe.spawn (fun () -> let cache = Hashtbl.create 4 in Hashtbl.replace cache 1 2)\n'),
 'mutable_snapshot': ('type snapshot = { mutable spot : float }\nlet snapshot = {spot=100.}\nlet worker = Domain.Safe.spawn (fun () -> snapshot.spot)\n',
                     'type snapshot = { spot : float }\nlet snapshot = {spot=100.}\nlet worker = Domain.Safe.spawn (fun () -> snapshot.spot)\n'),
 'aliased_scratch': ('let scratch = ref 0\nlet alias = scratch\nlet worker = Domain.Safe.spawn (fun () -> incr alias)\nlet () = incr scratch\n',
                    'let worker = Domain.Safe.spawn (fun () -> let scratch = ref 0 in let alias = scratch in incr alias; incr scratch)\n'),
}


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--version',action='version',version='oxcaml-mode-controls-v1')
 p.add_argument('--ocamlc',type=Path,required=True)
 p.add_argument('--output',type=Path,required=True)
 args=p.parse_args()
 compiler=args.ocamlc.resolve()
 records=[]
 with tempfile.TemporaryDirectory(prefix='risk-mode-') as directory:
  for name,(bad,good) in CASES.items():
   record=dict(case=name)
   for label,source in [('negative',bad),('positive',good)]:
    path=Path(directory)/(name+'_'+label+'.ml');path.write_text(source)
    proc=subprocess.run([str(compiler),'-color','never','-c',str(path)],cwd=directory,text=True,capture_output=True)
    record[label]=dict(source=source,returncode=proc.returncode,diagnostic=proc.stderr.replace(directory,'<temporary>'))
    if label=='negative':
     if proc.returncode!=2 or not any(s in proc.stderr for s in ('nonportable','contended','uncontended')) or 'Syntax error' in proc.stderr:
      raise AssertionError(record)
    elif proc.returncode!=0: raise AssertionError(record)
   records.append(record)
 report=dict(compiler=str(compiler),version=subprocess.check_output([str(compiler),'-version'],text=True).strip(),
             compiler_sha256=hashlib.sha256(compiler.read_bytes()).hexdigest(),controls=records)
 args.output.write_text(json.dumps(report,indent=2)+'\n')
 print('4 intended ownership violations rejected; 4 repaired controls compile')


if __name__=='__main__': main()
