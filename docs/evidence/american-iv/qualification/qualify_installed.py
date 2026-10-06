import hashlib,json,os,shutil,subprocess,time
from pathlib import Path
root=Path('/tmp/morphiq-american-iv');out=Path(__file__).resolve().parent
prefix=out/'install';consumer=out/'consumer';consumer.mkdir(exist_ok=True)
opam=['opam','exec','--switch=morphiq-risk-ml','--']
records=[]
def run(args,cwd=root):
 start=time.time();r=subprocess.run(args,cwd=cwd,capture_output=True,text=True,timeout=3600)
 records.append(dict(command=args,cwd=str(cwd),exit=r.returncode,seconds=time.time()-start,stdout=r.stdout,stderr=r.stderr))
 (out/'installed.json').write_text(json.dumps(records,indent=2)+'\n')
 if r.returncode:raise RuntimeError(r.stderr)
 return r.stdout
run(opam+['dune','install','--profile','release','--prefix',str(prefix)])
shutil.copyfile(root/'test/american_iv.ml',consumer/'client.ml')
dependency_lib=Path(subprocess.check_output(opam+['ocamlfind','query','zarith'],text=True).strip()).parent
env=['env','OCAMLPATH='+str(prefix/'lib'),'CAML_LD_LIBRARY_PATH='+os.pathsep.join(map(str,[prefix/'lib/stublibs',dependency_lib/'stublibs',dependency_lib/'zarith']))]
found=run(opam+env+['ocamlfind','query','morphiq_risk_ml'],consumer).strip()
assert Path(found).resolve()==(prefix/'lib/morphiq_risk_ml').resolve()
outputs=[]
for mode,compiler in [('native','ocamlopt'),('bytecode','ocamlc')]:
 exe=consumer/mode
 run(opam+env+['ocamlfind',compiler,'-package','morphiq_risk_ml,zarith','-linkpkg','-o',str(exe),'client.ml'],consumer)
 output=run(opam+env+[str(exe),str(root/'docs/evidence/american-iv/references.tsv'),'all','0.005','3'],consumer)
 assert output.endswith('TOTAL 30 30 0 0\n')
 outputs.append(output)
 (out/('installed-'+mode+'.log')).write_text(output)
assert outputs[0]==outputs[1]
(out/'installed-hashes.json').write_text(json.dumps({str(p.relative_to(out)):hashlib.sha256(p.read_bytes()).hexdigest() for p in [consumer/'client.ml',consumer/'native',consumer/'bytecode',*sorted((prefix/'lib/morphiq_risk_ml').rglob('*'))] if p.is_file()},indent=2)+'\n')
print('Installed native and bytecode: complete 30-row outcomes identical')
