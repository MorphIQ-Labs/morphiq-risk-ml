#!/usr/bin/env python3
"""Compare production DD fixture words across revisions, modes and profiles.

Build test/dd_word_replay.exe and .bc plus oracle/fixtures/dd.txt in _build and
_build_release in both roots first. This is exact compatibility evidence;
independent numerical error scoring belongs to the ordinary reference suite.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--version',action='version',version='dd-words-v1')
    p.add_argument('--baseline-source',type=Path,required=True)
    p.add_argument('--candidate-source',type=Path,required=True)
    p.add_argument('--output',type=Path,required=True)
    args=p.parse_args()
    report=dict(protocol='dd-words-v1',driver_sha256=sha(Path(__file__).read_bytes()),runs=[])
    expected=None
    harness=None
    for variant in ('baseline','candidate'):
        root=getattr(args,variant+'_source').resolve()
        code=(root/'test/dd_word_replay.ml').read_bytes()
        if harness is None: harness=code
        if code != harness: raise ValueError('harnesses differ')
        for profile,directory in [('development','_build'),('release','_build_release')]:
            build=root/directory/'default'
            fixture=build/'oracle/fixtures/dd.txt'
            inputs=[line for line in fixture.read_text().splitlines() if line and not line.startswith('#')]
            for mode in ('exe','bc'):
                binary=build/'test'/('dd_word_replay.'+mode)
                env=dict(os.environ,CAML_LD_LIBRARY_PATH=str(build/'lib/fp'))
                result=subprocess.check_output([str(binary),str(fixture)],env=env,timeout=180)
                lines=result.decode().splitlines()
                if [line.split('\t')[0] for line in lines] != inputs:
                    raise ValueError('missing/reordered/changed inputs')
                if any(len(line.split('\t'))!=2 or len(line.split('\t')[1].split())!=2 for line in lines):
                    raise ValueError('invalid output shape')
                if expected is None: expected=result
                if result != expected: raise ValueError('production DD result words changed')
                report['runs'].append(dict(variant=variant,profile=profile,mode=mode,rows=len(lines),
                    binary_sha256=sha(binary.read_bytes()),fixture_sha256=sha(fixture.read_bytes()),
                    result_sha256=sha(result),harness_sha256=sha(code),
                    sources={name:sha((root/name).read_bytes()) for name in ('lib/dd.ml','lib/split.ml')}))
                print(f'{variant} {profile} {mode}: {len(lines)} identical rows',flush=True)
    report['complete']=True
    args.output.write_text(json.dumps(report,indent=2)+'\n')


if __name__ == '__main__':
    main()
