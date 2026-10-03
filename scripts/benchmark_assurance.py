#!/usr/bin/env python3
"""Retain a manual A/B/B/A benchmark with provenance and all outcome counts."""
import argparse
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import subprocess
import time


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--baseline-revision", required=True)
    parser.add_argument("--same-contract", action="store_true",
                        help="A and B enforce the same certified IV contract")
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--count", type=int, default=64)
    parser.add_argument("--runs", type=int, default=5)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.count < 1 or args.runs < 1:
        parser.error("count and runs must be positive")
    root = Path(__file__).resolve().parents[1]
    sources = sorted(list((root / "lib").rglob("*.ml")) +
                     list((root / "lib").rglob("*.mli")) +
                     list((root / "lib").rglob("*.c")) +
                     list((root / "bench").glob("assurance*")) +
                     [root / "bench/dune", Path(__file__).resolve()])
    report = {
        "baseline_revision": args.baseline_revision,
        "candidate_parent": command("git", "-C", str(root), "rev-parse", "HEAD"),
        "source_sha256": {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
                          for p in sources},
        "platform": platform.platform(),
        "cpu": command("sysctl", "-n", "machdep.cpu.brand_string")
               if platform.system() == "Darwin" else platform.processor(),
        "ocaml": command("opam", "exec", "--switch=morphiq-risk-ml", "--", "ocamlopt", "-version"),
        "flambda": command("opam", "exec", "--switch=morphiq-risk-ml", "--", "ocamlopt", "-config-var", "flambda"),
        "optimization": "-O3; same benchmark source and switch for A and B",
        "order": "ABBA",
        "limits": [
            "Shared workstation, no isolated-host or production SLA claim.",
            "First batch follows outcome validation; it is not cold-process latency.",
            "Batch ns/op and sampled per-request latency are separate quantities.",
            "Clock/dispatch overhead is reported, not subtracted.",
            "Allocated words use current-domain Gc.counters; collection/heap samples use Gc.quick_stat. CPU time includes GC but does not isolate it.",
            "Heap words are runtime heap samples, not peak RSS or total process memory.",
            "Synthetic scalar cases are not a representative institutional portfolio.",
            ("A and B enforce the same exact-model IV rounding certificate."
             if args.same_contract else
             "A has a weaker IV contract; A/B quantifies the changed guarantee's cost, not equivalent-accuracy speed.")
        ],
        "runs": []
    }
    for label, binary in [("A1", args.baseline), ("B1", args.candidate),
                          ("B2", args.candidate), ("A2", args.baseline)]:
        invocation = [str(binary.resolve()), "--count", str(args.count), "--runs", str(args.runs)]
        load_before = os.getloadavg()
        started = time.monotonic()
        proc = subprocess.run(invocation, capture_output=True, text=True, check=True)
        rows = list(csv.DictReader(io.StringIO(proc.stdout)))
        if len(rows) != 61:
            raise RuntimeError(f"{label}: incomplete benchmark, {len(rows)} rows")
        totals = {}
        outcomes = []
        for line in proc.stderr.splitlines():
            model, regime, outcome, fraction = line.split()
            count, total = map(int, fraction.split("/"))
            if total != args.count:
                raise RuntimeError("inconsistent outcome denominator")
            totals[model, regime] = totals.get((model, regime), 0) + count
            outcomes.append(dict(model=model, regime=regime, outcome=outcome, count=count))
        if len(totals) != 12 or any(n != args.count for n in totals.values()):
            raise RuntimeError("missing benchmark outcome(s)")
        report["runs"].append(dict(
            label=label, command=invocation, load_before=load_before,
            load_after=os.getloadavg(), elapsed_seconds=time.monotonic()-started,
            rows=rows, outcomes=outcomes))
        print(f"{label} complete: {len(rows)} rows, all {12 * args.count} outcomes retained", flush=True)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n")


if __name__ == "__main__":
    main()
