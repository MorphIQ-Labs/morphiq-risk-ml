# morphiq-risk-ml

An internal experiment that rebuilds one slice of FerroRisk in OCaml. The slice and its exit criteria are defined in [SLICE.md](SLICE.md).

```sh
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
opam install dune alcotest qcheck-core qcheck-alcotest ocamlformat
eval "$(opam env --switch=morphiq-risk-ml)"
./oracle/fetch.sh        # FerroRisk reference fixtures from the pinned commit
python3 -m venv oracle/.venv && oracle/.venv/bin/pip install mpmath==1.3.0
oracle/.venv/bin/python oracle/gen_normal.py oracle/data/normal_reference.txt
oracle/.venv/bin/python oracle/convert_440.py oracle/data/440-candidates.jsonl.gz oracle/data/440-oracle.jsonl.gz oracle/data/european_price_reference.txt
oracle/.venv/bin/python oracle/convert_public_iv.py oracle/data/public_iv_reference.json oracle/data/public_iv_observed_envelope.json oracle/data/public_iv_reference.txt
oracle/.venv/bin/python oracle/convert_greeks.py oracle/data/greek_derivative_reference.json oracle/data/greek_reference.txt
oracle/.venv/bin/python oracle/gen_displaced.py oracle/data/displaced_price_reference.txt
dune build && dune test
```

Model definitions: [docs/model-contracts.md](docs/model-contracts.md). Results: [docs/results-slice.md](docs/results-slice.md).
