#!/usr/bin/env python3
"""Manual bounded planner/layout campaign. Expensive runs never enter default CI."""
import argparse
import datetime
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
    p.add_argument('--version',action='version',version='planner-measure-v1')
    p.add_argument('--scale-binary',type=Path,required=True)
    p.add_argument('--layout-binary',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--million',action='store_true')
    args=p.parse_args()
    report=dict(protocol='planner-measure-v1',platform=platform.platform(),machine=platform.machine(),
        source=subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),
        binaries={str(b):hashlib.sha256(b.read_bytes()).hexdigest() for b in (args.scale_binary,args.layout_binary)},runs=[])
    def run(binary,argv,label):
        command=[str(binary.resolve()),*argv]
        if platform.system()=='Darwin': command=['/usr/bin/time','-l',*command]
        started=datetime.datetime.now(datetime.timezone.utc).isoformat()
        load=os.getloadavg(); t=time.monotonic()
        result=subprocess.run(command,text=True,capture_output=True,check=True)
        record=dict(label=label,argv=argv,started=started,host_load=load,process_elapsed_s=time.monotonic()-t,result=json.loads(result.stdout))
        match=re.search(r'(\d+)\s+maximum resident set size',result.stderr)
        if match: record['peak_rss_bytes']=int(match[1])
        report['runs'].append(record)
        args.output.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps(record),flush=True)
    for count in (32,256,1024):
        for repeat in range(3):
            run(args.layout_binary,['--count',str(count)],f'layout-{repeat}')
    for workers in (1,2,4):
        for repeat in range(3):
            run(args.scale_binary,['--instruments','1000','--scenarios','3','--workers',str(workers),'--tile-rows','128'],'live-small')
    for mode in ('aggregate','stream'):
        run(args.scale_binary,['--instruments','10000','--scenarios','3','--workers','4','--tile-rows','128','--mode',mode],'live-medium')
    if args.million:
        run(args.scale_binary,['--instruments','1000000','--scenarios','1','--workers','4','--tile-rows','1024'],'live-million')
        run(args.scale_binary,['--instruments','1000000','--scenarios','3','--workers','4','--tile-rows','1024','--expiry'],'expiry-million-grid')
    live=[r['result'] for r in report['runs'] if r['label']=='live-small']
    if len({r['digest'] for r in live})!=1: raise ArithmeticError('worker-count/repeat summary mismatch')
    medium=[r['result'] for r in report['runs'] if r['label']=='live-medium']
    if len({r['digest'] for r in medium})!=1: raise ArithmeticError('stream/aggregate mismatch')
    report['complete']=True
    args.output.write_text(json.dumps(report,indent=2)+'\n')


if __name__=='__main__': main()
