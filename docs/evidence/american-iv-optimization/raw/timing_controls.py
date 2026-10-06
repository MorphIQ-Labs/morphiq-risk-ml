import math,subprocess,time,os,signal
EXPECTED={f'{a}/{b}' for a in ['call-100-0.05-american','american-put','cash-terminal-american'] for b in ['price','solve','end-to-end']}
def parse(output):
 checks=[];samples=[]
 for line in output.splitlines():
  cells=line.split()
  if cells and cells[0]=='CHECK':
   if len(cells)!=5 or cells[1] not in ['call-100-0.05-american','american-put','cash-terminal-american']:raise ValueError('check identity')
   if not all(math.isfinite(float.fromhex(x)) for x in cells[2:4]):raise ValueError('nonfinite check')
   checks.append(line);continue
  if len(cells)!=7 or cells[0]!='TIME':raise ValueError('malformed timing')
  _,name,round_,n,wall,cpu,alloc=cells
  if name not in EXPECTED or not 1<=int(round_)<=3 or int(n)<=0:raise ValueError('timing identity')
  values=list(map(float,[wall,cpu,alloc]))
  if not all(math.isfinite(x) and x>=0 for x in values):raise ValueError('nonfinite timing')
  samples.append(dict(name=name,round=int(round_),n=int(n),wall_ns=values[0],cpu_ns=values[1],allocated_bytes=values[2]))
 if len(checks)!=3 or len({x.split()[1] for x in checks})!=3:raise ValueError('incomplete checks')
 if len(samples)!=27 or len({(s['name'],s['round']) for s in samples})!=27:raise ValueError('incomplete timing')
 return checks,samples

def verify(checks,references):
 from fractions import Fraction
 for line in checks:
  _,name,lo,hi,n=line.split()
  lo,hi=map(lambda x:Fraction(float.fromhex(x)),(lo,hi))
  reflo,refhi=references[name]
  if not(lo<=reflo<=refhi<=hi and hi-lo<=Fraction(.005) and 2<=int(n)<=64):
   raise ValueError('reference/width/work rejection')

def acceptance(ratio,maximum):
 if not math.isfinite(ratio) or ratio>maximum:raise ValueError('frozen performance criteria unmet')

def execute(args,stdout,stderr,timeout):
 with stdout.open('w') as so,stderr.open('w') as se:
  try:p=subprocess.Popen(args,stdout=so,stderr=se,env={**os.environ,'OCAMLRUNPARAM':'v=0x400'})
  except OSError as e:raise RuntimeError('timing startup failed') from e
  deadline=time.monotonic()+timeout
  while True:
   pid,status,usage=os.wait4(p.pid,os.WNOHANG)
   if pid:break
   if time.monotonic()>=deadline:
    os.kill(p.pid,signal.SIGKILL)
    _,status,usage=os.wait4(p.pid,0)
    p.returncode=os.waitstatus_to_exitcode(status)
    raise RuntimeError('timing timeout')
   time.sleep(.05)
  p.returncode=os.waitstatus_to_exitcode(status)
 if p.returncode:raise RuntimeError('timing process failed')
 checks,samples=parse(stdout.read_text())
 return checks,samples,dict(peak_rss=usage.ru_maxrss,user_seconds=usage.ru_utime,system_seconds=usage.ru_stime)

if __name__=='__main__':
 import tempfile,unittest,sys
 from pathlib import Path
 good=''.join(f'CHECK {n} 0x1p+0 0x0p+0 9\n' for n in ['call-100-0.05-american','american-put','cash-terminal-american'])+''.join(f'TIME {n} {r} 100 1 1 1\n' for n in sorted(EXPECTED) for r in range(1,4))
 class Controls(unittest.TestCase):
  def test_good(self):self.assertEqual(len(parse(good)[1]),27)
  def test_truncated(self):
   with self.assertRaisesRegex(ValueError,'incomplete timing'):parse('\n'.join(good.splitlines()[:-1]))
  def test_malformed(self):
   with self.assertRaisesRegex(ValueError,'malformed timing'):parse(good+'bad\n')
  def test_nonfinite(self):
   with self.assertRaisesRegex(ValueError,'nonfinite timing'):parse(good.replace('100 1 1 1','100 nan 1 1',1))
  def test_duplicate(self):
   lines=good.splitlines();lines[-1]=lines[-2]
   with self.assertRaisesRegex(ValueError,'incomplete timing'):parse('\n'.join(lines))
  def test_reference_and_work(self):
   from fractions import Fraction
   refs={'x':(Fraction(1,5),Fraction(1,5))}
   verify(['CHECK x 0x1.96p-3 0x1.9ap-3 6'],refs)
   for line in ['CHECK x 0x1p-3 0x1p-4 6','CHECK x 0x1p-3 0x1p-1 6','CHECK x 0x1.96p-3 0x1.9ap-3 65']:
    with self.assertRaisesRegex(ValueError,'reference/width/work rejection'):verify([line],refs)
  def test_impossible_criterion(self):
   with self.assertRaisesRegex(ValueError,'frozen performance criteria unmet'):acceptance(1.0,0.0)
  def test_successful_process_resource_reap(self):
   with tempfile.TemporaryDirectory() as d:
    checks,samples,usage=execute([sys.executable,'-c','print('+repr(good)+',end="")'],Path(d)/'out',Path(d)/'err',2)
    self.assertEqual(len(samples),27)
    self.assertGreater(usage['peak_rss'],0)
  def test_process_failures(self):
   with tempfile.TemporaryDirectory() as d:
    out=Path(d)/'out';err=Path(d)/'err'
    for args,reason in [(['/missing-american-cert-benchmark'],'startup failed'),([sys.executable,'-c','raise SystemExit(2)'],'process failed'),([sys.executable,'-c','import time; print("partial",flush=True); time.sleep(5)'],'timeout')]:
     with self.assertRaisesRegex(RuntimeError,reason):execute(args,out,err,.2)
    self.assertEqual(out.read_text(),'partial\n')
 unittest.main()
