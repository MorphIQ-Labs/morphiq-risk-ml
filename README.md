# morphiq-risk-ml

An internal experiment that rebuilds one slice of FerroRisk in OCaml. The slice and its exit criteria are defined in [SLICE.md](SLICE.md).

```sh
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
opam install dune alcotest qcheck-core qcheck-alcotest ocamlformat
eval "$(opam env --switch=morphiq-risk-ml)"
dune build && dune test          # every oracle is committed under oracle/fixtures
dune exec --release bench/bench.exe

# Regenerating oracles (mpmath 1.3.0), and the optional FerroRisk cross-check:
python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0
oracle/build.sh                  # regenerates fixtures and oracle/MANIFEST.json
oracle/.venv/bin/python scripts/manifest.py check
scripts/ferro_crosscheck.sh      # needs oracle/fetch.sh and the convert_* scripts
```

The public API is `Morphiq_risk` (see `lib/morphiq_risk.mli`); `Morphiq_risk.Internal` is unstable. Model definitions: [docs/model-contracts.md](docs/model-contracts.md). Oracles: [docs/oracles.md](docs/oracles.md). Error analysis: [docs/error-analysis.md](docs/error-analysis.md). Stability: [docs/stability.md](docs/stability.md). Changes: [CHANGELOG.md](CHANGELOG.md). Results: [docs/results-slice.md](docs/results-slice.md).
