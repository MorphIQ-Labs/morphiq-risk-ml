# morphiq-risk-ml

An internal experiment that rebuilds one slice of FerroRisk in OCaml. The slice and its exit criteria are defined in [SLICE.md](SLICE.md).

Contributor and agent guidance: [AGENTS.md](AGENTS.md). `CLAUDE.md` delegates to that same contract.

```sh
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
eval "$(opam env --switch=morphiq-risk-ml)"
opam install . --deps-only --with-test --locked   # versions pinned in morphiq_risk_ml.opam.locked
opam install ocamlformat.0.27.0
dune build && dune test          # needs python3 stdlib for exact-rational bound checks
dune build @fmt
dune exec scripts/mutation/mutation.exe -- --core # seven required CI mutants
dune exec scripts/mutation/mutation.exe   # full catalog (optional locally)
dune exec --release bench/bench.exe

# Regenerating oracles (mpmath 1.3.0), and the optional FerroRisk cross-check:
python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0
oracle/build.sh                  # regenerates fixtures and oracle/MANIFEST
scripts/ferro_crosscheck.sh      # needs oracle/fetch.sh and the convert_* scripts
```

The public API is `Morphiq_risk` (see `lib/morphiq_risk.mli`); `Morphiq_risk.Internal` is unstable. Model definitions: [docs/model-contracts.md](docs/model-contracts.md). Oracles: [docs/oracles.md](docs/oracles.md). Error analysis: [docs/error-analysis.md](docs/error-analysis.md). Stability: [docs/stability.md](docs/stability.md). Changes: [CHANGELOG.md](CHANGELOG.md). Results: [docs/results-slice.md](docs/results-slice.md).

Prices and finite Greeks in the committed corpora are checked against per-input analytical bounds, with exact-rational rounded-kernel checks and extra-bit references. Historical ULP targets remain additional quality gates. Positive IV results now require a runtime certificate of correct binary64 rounding; unresolved cases fail explicitly. Production-domain coverage and independent review still have the limitations listed in the [certification status](docs/error-analysis.md#certification-status-and-remaining-proof-obligations).

Ordinary CI runs the full test suite on all three platforms, formatting, and the seven [core mutation checks](docs/mutation-policy.md). The full mutation catalog is a separate manual/weekly workflow; it does not run on each PR or push.

The [research library](docs/research/README.md) contains the collected reference PDFs, their source URLs and checksums, canonical filenames, and a separate list of book and implementation references.

The [numerical backend contract](docs/numerical-backend-contract.md) defines required arithmetic semantics, optimization assessment, AD/FFI obligations, and conformance evidence. Native and bytecode arithmetic probes run in the ordinary suite.

The [runtime enclosure foundation](docs/runtime-enclosures.md) and independent [model evaluator](docs/model-enclosures.md) support [certified IV acceptance](docs/certified-iv.md), including original-input boundary decisions. The fast price and Greek APIs remain separate from those runtime certificates.

The [financial type audit](docs/type-boundary-audit.md) records enforced invariants, trusted raw-value labeling, all Greek units, and remaining caller obligations. Veta retains both its time unit and volatility coordinate.

The candidate [production adapter](docs/production-boundary-design.md) requires
explicit typed accuracy limits for prices and smooth Greeks and returns private
certificates with outward absolute error. It preserves certified IV outcomes.
Expiry/zero-volatility Greeks are explicitly unsupported by this adapter; its
availability and institutional acceptance limits remain documented.

## Scenario-planner integration

`Planner.compile` freezes a portfolio, typed market factors and paired or
Cartesian scenarios into an inspectable bounded plan. `Planner.execute` runs
scalar-certified prices/Greeks sequentially or across domains, streams stable
outcomes and emits deterministic weighted enclosures with explicit completeness.
`Batch` also supports externally supplied IV requests. See the
[scenario contract](docs/scenario-planner.md) for date rolls, units, resources,
failures and replay. The work is on `integration/scenario-planner`; it has not
been merged into main or accepted for institutional deployment.

[Planner qualification](docs/results-planner.md) records the independent certificates,
million-instrument campaign, memory/throughput limits and isolated
[OxCaml decision](experiments/oxcaml/README.md).
