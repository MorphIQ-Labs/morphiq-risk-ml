#!/usr/bin/env python3
"""Prepare an isolated, reviewable OxCaml copy; never edits production sources."""
import argparse
import io
from pathlib import Path
import shutil
import subprocess
import tarfile


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--version',action='version',version='oxcaml-prepare-v1')
 p.add_argument('--source',default='HEAD')
 p.add_argument('--destination',type=Path,required=True)
 p.add_argument('--portable',action='store_true')
 p.add_argument('--canonical-parallel',action='store_true')
 args=p.parse_args()
 if args.canonical_parallel and not args.portable: p.error("--canonical-parallel requires --portable")
 root=Path(__file__).resolve().parents[2]
 destination=args.destination.resolve()
 if destination.exists(): raise SystemExit('destination must not exist')
 if root==destination or root in destination.parents: raise SystemExit('destination must be outside the source checkout')
 commit=subprocess.check_output(['git','rev-parse',args.source+'^{commit}'],cwd=root,text=True).strip()
 archive=subprocess.check_output(['git','archive',commit],cwd=root)
 destination.mkdir(parents=True)
 with tarfile.open(fileobj=io.BytesIO(archive)) as source:
  source.extractall(destination,filter='data')
 if args.portable:
  subprocess.run(['git','apply',str(root/'experiments/oxcaml/portable-numerics.patch')],cwd=destination,check=True)
  shutil.copyfile(root/'experiments/oxcaml/worker.ml.in',destination/'bench/ox_worker.ml')
  libraries='morphiq_risk'
  if args.canonical_parallel:
   for name in ('elementary','dd','normalised_black'):
    path=destination/'lib'/f'{name}.ml'
    path.write_text('module Iarray = Stdlib_stable.Iarray\n'+path.read_text())
   path=destination/'lib/dune';path.write_text(path.read_text().replace('(libraries morphiq_fp)','(libraries morphiq_fp stdlib_stable)'))
   worker=destination/'bench/ox_worker.ml'
   source=worker.read_text();source=source[:source.index('let () =')]
   source+='''let parallel_tile par =
  let #(a,b) = Parallel.fork_join2 par (fun _ -> tile inputs) (fun _ -> tile inputs) in
  if a<>b || a<>tile inputs then failwith "canonical fork/join mismatch";
  if List.exists Result.is_error (snd a) then failwith "pricing refusal";
  fst a + fst b
let () =
  let result = Parallel_scheduler.with_parallel ~max_workers:2 parallel_tile in
  Printf.printf "canonical mode-checked fork/join: %d certified prices\\n" result
'''
   worker.write_text(source)
   libraries+=' parallel parallel.scheduler'
  with (destination/'bench/dune').open('a') as stream:
   stream.write(f'\n(executable (name ox_worker) (modules ox_worker) (libraries {libraries}))\n')
 (destination/'EXPERIMENT-SOURCE').write_text(commit+'\n')
 print(destination)


if __name__=='__main__': main()
