#!/usr/bin/env python3
"""Prepare an isolated, reviewable OxCaml copy; never edits production sources."""
import argparse
import io
from pathlib import Path
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
 if args.portable: p.error('historical portable patch retired after source audit; see README.md')
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
 (destination/'EXPERIMENT-SOURCE').write_text(commit+'\n')
 print(destination)


if __name__=='__main__': main()
