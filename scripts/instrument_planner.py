#!/usr/bin/env python3
"""Generate test-only planner wrappers; production source and API stay untouched."""
import hashlib
from pathlib import Path
import sys

if sys.argv[1] == '--signature':
    print('open Morphiq_risk\nmodule type S = sig')
    print(Path(sys.argv[2]).read_text())
    print('end')
    raise SystemExit(0)

source = Path(sys.argv[1]).read_text()

def replace_once(text, old, new):
    if text.count(old) != 1:
        raise ValueError('planner instrumentation site missing/ambiguous: ' + old)
    return text.replace(old, new)

source = replace_once(source, 'let execute t ~workers ~cancellation ~sink =', '''let evaluate_tile_original = evaluate_tile
let evaluate_tile t work =
  Planner_probe.evaluate work.id (fun () ->
    let result = evaluate_tile_original t work in
    (match result with
    | Error _ -> ()
    | Ok rows -> Planner_probe.retain
        (Array.fold_left (fun n row -> n + max 1 (List.length row.outcomes)) 0 rows));
    result)
let execute t ~workers ~cancellation ~sink =''')
source = replace_once(source, 'let run_waves ~max_workers ~tiles ~workers ~check_cancel ~run_tile ~accept =',
                      'module Domain = Planner_probe.Domains\n\nlet run_waves ~max_workers ~tiles ~workers ~check_cancel ~run_tile ~accept =')
source = replace_once(source, 'next := !next + n', 'Planner_probe.release_wave ();\n        next := !next + n')
print('open Morphiq_risk\nopen Morphiq_risk.Internal')
print('let instrumented_source_sha256 = "' + hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest() + '"')
print(source)
print('''
let execute_original = execute
let execute t ~workers ~cancellation ~sink =
  Fun.protect ~finally:Planner_probe.release_wave
    (fun () -> execute_original t ~workers ~cancellation ~sink)
''')
