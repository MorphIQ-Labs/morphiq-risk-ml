"""Manual failure controls for retained allocation measurement protocols."""
import importlib.util
import json
import subprocess
import sys
import tempfile
from pathlib import Path

root = Path(sys.argv[1]).resolve()
raw = json.loads(Path(sys.argv[2]).read_text())
spec = importlib.util.spec_from_file_location('benchmark', root/'scripts/benchmark_fast_allocation.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
for bench in ('fast_batch', 'fast_planner', 'shared_portfolio'):
    text = next(r['raw'] for r in raw['runs'] if r['bench'] == bench)
    module.parse(text, bench)
    lines = text.splitlines()
    first_time = next(line for line in lines if line.startswith('TIME'))
    bad_time = first_time.split(); bad_time[-1] = 'nan'
    for name, bad in [('truncated', '\n'.join(lines[:-1])),
                      ('duplicate', text.rstrip()+'\n'+first_time),
                      ('nonfinite', text.replace(first_time, ' '.join(bad_time))),
                      ('missing-check', '\n'.join(line for line in lines if not line.startswith('CHECK')))]:
        try:
            module.parse(bad, bench)
        except ValueError:
            print(bench, name, 'rejected')
        else:
            raise AssertionError((bench, name))
with tempfile.TemporaryDirectory() as tmp:
    base = Path(tmp)
    expected = 'fixture-a\t0000000000000000 0000000000000001\nfixture-b\t0000000000000002 0000000000000003\n'
    for variant in ('baseline', 'candidate'):
        source = base/variant
        for name in ('test/dd_word_replay.ml','lib/dd.ml','lib/split.ml'):
            p = source/name; p.parent.mkdir(parents=True, exist_ok=True); p.write_text('control')
        for build in ('_build', '_build_release'):
            directory = source/build/'default'
            fixture = directory/'oracle/fixtures/dd.txt'; fixture.parent.mkdir(parents=True)
            fixture.write_text('fixture-a\nfixture-b\n')
            for mode in ('exe', 'bc'):
                p = directory/'test'/('dd_word_replay.'+mode); p.parent.mkdir(exist_ok=True)
                p.write_text('#!'+sys.executable+'\nprint('+repr(expected)+',end="")\n'); p.chmod(0o755)
    cmd = [sys.executable, str(root/'scripts/compare_dd_words.py'), '--baseline-source',str(base/'baseline'), '--candidate-source',str(base/'candidate'),'--output',str(base/'result.json')]
    subprocess.run(cmd, check=True, capture_output=True)
    target = base/'candidate/_build_release/default/test/dd_word_replay.bc'
    for name, bad, reason in [('missing', expected.splitlines()[0]+'\n', 'missing/reordered/changed inputs'),
                             ('reordered', '\n'.join(reversed(expected.splitlines()))+'\n', 'missing/reordered/changed inputs'),
                             ('changed-word', expected.replace('0000000000000003','0000000000000004'), 'production DD result words changed')]:
        target.write_text('#!'+sys.executable+'\nprint('+repr(bad)+',end="")\n')
        result = subprocess.run(cmd, text=True, capture_output=True)
        assert result.returncode != 0 and reason in result.stderr, (name, result)
        print('dd-words', name, 'rejected')
print('all protocol controls passed')
