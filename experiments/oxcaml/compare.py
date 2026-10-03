#!/usr/bin/env python3
"""Manual compiler/representation comparison, with exact outcome checks."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import subprocess
import time


def main():
 p=argparse.ArgumentParser(description=__doc__)
 p.add_argument('--version',action='version',version='planner-compiler-compare-v1')
 p.add_argument('--variant',action='append',required=True,help='NAME=build/default/bench directory')
 p.add_argument('--output',type=Path,required=True)
 args=p.parse_args()
 variants={name:Path(path).resolve() for name,path in (entry.split('=',1) for entry in args.variant)}
 if len(variants)!=len(args.variant):p.error('duplicate variant')
 report=dict(protocol='planner-compiler-compare-v1',host=platform.platform(),runs=[],binaries={})
 for name,directory in variants.items():
  report['binaries'][name]={exe:hashlib.sha256((directory/exe).read_bytes()).hexdigest() for exe in ('planner_scale.exe','batch_layout.exe')}
 def run(name,exe,argv,repeat,kind):
  command=[str(variants[name]/exe),*argv]
  if platform.system()=='Darwin': command=['/usr/bin/time','-l',*command]
  start=time.monotonic();load=os.getloadavg()
  r=subprocess.run(command,text=True,capture_output=True,check=True)
  entry=dict(variant=name,kind=kind,repeat=repeat,argv=argv,host_load=load,process_s=time.monotonic()-start,result=json.loads(r.stdout))
  rss=re.search(r'(\d+)\s+maximum resident set size',r.stderr)
  if rss:entry['peak_rss_bytes']=int(rss[1])
  report['runs'].append(entry);args.output.write_text(json.dumps(report,indent=2)+'\n')
 for repeat in range(3):
  # Reverse alternate rounds to expose order/warmth effects instead of always
  # giving one compiler the same first/last position.
  order=list(variants)
  if repeat%2:order.reverse()
  for name in order:
   run(name,'batch_layout.exe',['--count','256'],repeat,'scalar-and-layout')
   for workers in (1,4):
    run(name,'planner_scale.exe',['--instruments','256','--scenarios','3','--workers',str(workers),'--tile-rows','64'],repeat,'planner')
 for name in variants:
  for repeat in range(10):
   run(name,'planner_scale.exe',['--instruments','32','--scenarios','3','--workers','4','--tile-rows','16'],repeat,'small-job-latency')
 for kind in ('planner','small-job-latency'):
  digests={r['result']['digest'] for r in report['runs'] if r['kind']==kind}
  if len(digests)!=1:raise ArithmeticError((kind,'different aggregate output'))
 report['complete']=True;args.output.write_text(json.dumps(report,indent=2)+'\n')
 print('all compiler/representation outputs identical; measurements retained')


if __name__=='__main__':main()
