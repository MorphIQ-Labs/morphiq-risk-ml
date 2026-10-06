import math,subprocess,time
EXPECTED={f'{a}/{b}' for a in ['call','terminal-put','expiry'] for b in ['admission','price','end-to-end']}
def parse(output):
 checks=[];samples=[]
 for line in output.splitlines():
  cells=line.split()
  if cells and cells[0]=='CHECK':
   if len(cells)!=4 or cells[1] not in ['call','terminal-put','expiry']:raise ValueError('check identity')
   if not all(math.isfinite(float.fromhex(x)) for x in cells[2:]):raise ValueError('nonfinite check')
   checks.append(line);continue
  if len(cells)!=7 or cells[0]!='TIME':raise ValueError('malformed timing')
  _,name,round_,n,wall,cpu,alloc=cells
  if name not in EXPECTED or not 1<=int(round_)<=5 or int(n)<=0:raise ValueError('timing identity')
  values=list(map(float,[wall,cpu,alloc]))
  if not all(math.isfinite(x) and x>=0 for x in values):raise ValueError('nonfinite timing')
  samples.append(dict(name=name,round=int(round_),n=int(n),wall_ns=values[0],cpu_ns=values[1],allocated_bytes=values[2]))
 if len(checks)!=3 or len({x.split()[1] for x in checks})!=3:raise ValueError('incomplete checks')
 if len(samples)!=45 or len({(s['name'],s['round']) for s in samples})!=45:raise ValueError('incomplete timing')
 return checks,samples

def execute(args,stdout,stderr,timeout):
 with stdout.open('w') as so,stderr.open('w') as se:
  try:r=subprocess.run(args,stdout=so,stderr=se,timeout=timeout)
  except subprocess.TimeoutExpired:raise RuntimeError('timing timeout')
  except OSError as e:raise RuntimeError('timing startup failed') from e
 if r.returncode:raise RuntimeError('timing process failed')
 return parse(stdout.read_text())

if __name__=='__main__':
 import tempfile,unittest,sys
 from pathlib import Path
 good=''.join(f'CHECK {n} 0x1p+0 0x0p+0\n' for n in ['call','terminal-put','expiry'])+''.join(f'TIME {n} {r} 100 1 1 1\n' for n in sorted(EXPECTED) for r in range(1,6))
 class Controls(unittest.TestCase):
  def test_good(self):self.assertEqual(len(parse(good)[1]),45)
  def test_truncated(self):
   with self.assertRaisesRegex(ValueError,'incomplete timing'):parse('\n'.join(good.splitlines()[:-1]))
  def test_malformed(self):
   with self.assertRaisesRegex(ValueError,'malformed timing'):parse(good+'bad\n')
  def test_nonfinite(self):
   with self.assertRaisesRegex(ValueError,'nonfinite timing'):parse(good.replace('100 1 1 1','100 nan 1 1',1))
  def test_duplicate(self):
   lines=good.splitlines();lines[-1]=lines[-2]
   with self.assertRaisesRegex(ValueError,'incomplete timing'):parse('\n'.join(lines))
  def test_process_failures(self):
   with tempfile.TemporaryDirectory() as d:
    out=Path(d)/'out';err=Path(d)/'err'
    for args,reason in [(['/missing-american-cert-benchmark'],'startup failed'),([sys.executable,'-c','raise SystemExit(2)'],'process failed'),([sys.executable,'-c','import time; print("partial",flush=True); time.sleep(5)'],'timeout')]:
     with self.assertRaisesRegex(RuntimeError,reason):execute(args,out,err,.2)
    self.assertEqual(out.read_text(),'partial\n')
 unittest.main()
