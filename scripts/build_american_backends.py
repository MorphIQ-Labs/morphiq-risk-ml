#!/usr/bin/env python3
"""Construct a fresh optional American DGTSV experiment; production tree is untouched."""
import argparse, hashlib, json, os
from pathlib import Path
import shutil, subprocess, urllib.request

REV='6ec7f2bc4ecf4c4a93496aa2fa519575bc0e39ca'
ROOT=Path(__file__).resolve().parent.parent

def run(args,cwd):
    subprocess.run(args,cwd=cwd,check=True)
def sha(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def replace_once(path,old,new):
    text=path.read_text()
    if text.count(old)!=1:raise ValueError('unexpected source anchor: '+str(path))
    path.write_text(text.replace(old,new,1))
def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--version',action='version',version='american-backends-builder 1')
    args=p.parse_args();dest=args.output.resolve()
    if dest.is_relative_to(ROOT):p.error('output must be outside source')
    dest.mkdir(parents=True,exist_ok=False)
    tree=dest/'source';tree.mkdir()
    names=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
    snapshot={}
    for name in sorted(set(names)-{''}):
        source=ROOT/name
        if source.is_file():
            target=tree/name;target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(source,target)
            snapshot[name]=sha(source)
    upstream=dest/'upstream';upstream.mkdir()
    hashes={}
    for name,urlpart in [('dgtsv.f','SRC/dgtsv.f'),('LICENSE','LICENSE')]:
        data=urllib.request.urlopen(f'https://raw.githubusercontent.com/Reference-LAPACK/lapack/{REV}/{urlpart}',timeout=30).read()
        (upstream/name).write_bytes(data);hashes[name]=sha(upstream/name)
    # Frozen hashes are checked before compilation, including the upstream notice.
    expected=json.loads((ROOT/'bench/american_backends/upstream.json').read_text())
    if hashes!=expected['sha256']:raise ValueError('upstream identity mismatch')
    flags=['-O3','-ffp-contract=off','-fno-fast-math','-fno-tree-vectorize','-fno-tree-slp-vectorize','-fPIC']
    run(['gfortran',*flags,'-c',str(upstream/'dgtsv.f'),'-o',str(dest/'dgtsv.o')],dest)
    run(['ar','rcs',str(tree/'lib/libbackend_lapack.a'),str(dest/'dgtsv.o')],dest)
    original=tree/'lib/american_policy.ml';shutil.copyfile(original,tree/'lib/american_policy_original.ml')
    shutil.copyfile(tree/'lib/american_policy.mli',tree/'lib/american_policy_original.mli')
    shutil.copyfile(ROOT/'test/american_policy_reference.ml',tree/'lib/american_policy_reference.ml')
    shutil.copyfile(ROOT/'bench/american_backends/owner.ml',original)
    with (tree/'lib/american_policy.mli').open('a') as f:f.write('\nval context : t -> local:float -> unit\n')
    shutil.copyfile(ROOT/'bench/american_backends/lapack_stubs.c',tree/'lib/backend_lapack_stubs.c')
    replace_once(tree/'lib/dune','american_policy_stubs)','american_policy_stubs\n   backend_lapack_stubs)')
    replace_once(tree/'lib/dune',' (c_library_flags -lm)',' (foreign_archives backend_lapack)\n (c_library_flags -lm)')
    replace_once(tree/'lib/early_exercise.ml','    let policy_rows phase first last =',
      '    American_policy.context policy_state ~local:c.local;\n    let policy_rows phase first last =')
    shutil.copyfile(ROOT/'bench/american_backends/controls.ml',tree/'bench/backend_controls.ml')
    with (tree/'bench/dune').open('a') as f:
        f.write('\n(executable (name backend_controls) (modules backend_controls) (modes byte_complete exe) (libraries morphiq_risk))\n')
    metadata=dict(source_commit=subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
      source_files=snapshot,upstream=expected,fortran=subprocess.check_output(['gfortran','--version'],text=True),
      fortran_flags=flags,patches={name:sha(tree/name) for name in ('lib/american_policy.ml','lib/american_policy.mli','lib/early_exercise.ml','lib/dune','lib/backend_lapack_stubs.c')})
    (dest/'build-manifest.json').write_text(json.dumps(metadata,indent=2)+'\n')
    run(['opam','exec','--switch=morphiq-risk-ml','--','dune','build','--profile','release',
         'bench/backend_requests.exe','bench/backend_requests.bc.exe','bench/backend_micro.exe','bench/backend_micro.bc.exe','bench/backend_controls.exe','bench/backend_controls.bc.exe','bench/backend_contracts.exe','bench/backend_contracts.bc.exe'],tree)
    print(tree/'_build/default/bench/backend_requests.exe')
if __name__=='__main__':main()
