import hashlib,json,subprocess,shutil
from pathlib import Path
root=Path('/tmp/morphiq-american-iv-opt');out=Path(__file__).resolve().parent;consumer=out/'consumer';prefix=out/'install'
shutil.copyfile(root/'test/american_iv_negative_yield.ml',consumer/'negative_yield.ml')
env=['opam','exec','--switch=morphiq-risk-ml','--','env','OCAMLPATH='+str(prefix/'lib'),'CAML_LD_LIBRARY_PATH='+str(prefix/'lib/stublibs')+':/Users/stephen/.opam/morphiq-risk-ml/lib/stublibs']
records=[];outputs=[]
for mode,compiler in [('native','ocamlopt'),('bytecode','ocamlc')]:
 exe=consumer/('negative-yield-'+mode)
 for args in [['ocamlfind',compiler,'-package','morphiq_risk_ml,zarith','-linkpkg','-o',str(exe),'negative_yield.ml'],[str(exe),str(root/'docs/evidence/american-iv/negative-yield/references.tsv')]]:
  p=subprocess.run(env+args,cwd=consumer,capture_output=True,text=True,timeout=60)
  records.append(dict(command=env+args,exit=p.returncode,stdout=p.stdout,stderr=p.stderr))
  (out/'negative-yield-installed.json').write_text(json.dumps(records,indent=2)+'\n')
  assert p.returncode==0,p.stderr
 outputs.append(p.stdout)
 (out/('negative-yield-installed-'+mode+'.log')).write_text(p.stdout)
 assert p.stdout.endswith('2 independent negative-yield quotes, 4 exercise-contract checks passed\n')
assert outputs[0]==outputs[1]
print('negative-yield installed native/bytecode matched')
