# morphiq-risk-ml

An OCaml library for European option pricing, implied volatility, analytic
Greeks, and deterministic portfolio scenarios.

The library implements Black–Scholes–Merton, Black-76, displaced Black, and
Bachelier from their mathematical definitions. Model admission, volatility
coordinates, and Greek units are represented in the public types. FerroRisk is
an optional comparison implementation; it is not a dependency.

**Status:** pre-1.0, with version 0.3.0 currently unreleased. The supported
capabilities and numerical limitations below apply independently of release
status. The [experimental candidate qualification](docs/candidate-0.3.0.md)
records the exact tested source and evidence. This project does not claim
institutional deployment approval.

## Capabilities

| Capability | Contract |
| --- | --- |
| Prices | Calls and puts, including expiry and zero volatility |
| Implied volatility | Positive roots require a runtime certificate of correct binary64 rounding; unresolved cases fail explicitly |
| Analytic Greeks | Delta, gamma, theta, vega, rho, vanna, volga, charm, veta, and color, with model-specific volatility and time units |
| Numerical acceptance | `Production` requires caller-selected absolute error limits and returns private value/error certificates or explicit failures |
| Exchange prices | Certified scalar two-asset European prices with typed correlation and an explicit currency error limit; [scope and limits](docs/exchange-prices.md) |
| Fast price batches | One-shot or frozen compiled requests with admission reuse and explicit failures; [contract](docs/fast-batch.md). No runtime error certificate |
| Batch evaluation | Typed price, Greek, and IV requests; [shared preparation for multiple certified outputs](docs/shared-certification.md) |
| Scenario planning | Frozen portfolios and market inputs, paired or Cartesian shocks, bounded parallel execution, streamed outcomes, and deterministic weighted enclosures |

The planner rolls valuation dates forward with fixed expiries and frozen
markets. It reports post-expiry requests explicitly. Economic P&L, settlement,
surface calibration, American exercise, stochastic-volatility models, SIMD,
distributed execution, and durable resume are outside the current API.

## Build and install from source

The qualified toolchain is **OCaml 5.3.0 with Flambda**. You need opam and a C
compiler; development checks also need Python 3 and the pinned test dependencies.
CI runs on Linux x86-64, Linux ARM64, and macOS ARM64.

```sh
git clone https://github.com/MorphIQ-Labs/morphiq-risk-ml.git
cd morphiq-risk-ml

# Create this switch once; reuse it if it already exists.
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
opam install --switch=morphiq-risk-ml . --locked
```

The opam/Dune package is `morphiq_risk_ml`; the OCaml module is `Morphiq_risk`.
Add `(libraries morphiq_risk_ml)` to a consuming Dune executable or library.
For reproducible integration, record the exact source commit and dependency
lockfile. These instructions install the checkout, not a published opam release.

## Price with an explicit error limit

```ocaml
open Morphiq_risk

let price_call () =
  match Vol.lognormal 0.2 with
  | Error refusal -> Error (Production.Invalid_input refusal)
  | Ok volatility -> (
      match Production.Black76.admit
        { forward = 100.; strike = 100.; time_to_expiry = 1.; rate = 0.02 }
      with
      | Error error -> Error error
      | Ok admitted ->
          Production.Black76.evaluate admitted Side.Call volatility
            Production.Price ~max_error:1e-10)

let () =
  match price_call () with
  | Ok certificate ->
      Printf.printf "Price %.12g; absolute numerical error <= %.3g\n"
        certificate.value certificate.absolute_error
  | Error _ ->
      failwith "Request refused: inspect the Production.error before retrying"
```

The example's error limit is illustrative; choose one appropriate to your units
and application. Admission validates inputs but does not guarantee a successful
evaluation. The certificate bounds numerical error in the exact model, not
market-data or model risk. Applications must handle each `Production.error` and
`Iv.t` outcome explicitly.

Run the included portfolio example with one, two, or four workers:

```sh
opam exec --switch=morphiq-risk-ml -- dune exec examples/scenario_job.exe -- --workers 2
```

## Numerical guarantees and limits

`Production` is the integration boundary for enforced accuracy. Certified prices
cover expiry and zero variance where arithmetic resolves; certified smooth
Greeks require positive maturity and volatility. Requests may fail because of
unsupported boundaries, unresolved arithmetic, or an unmet accuracy limit.

The fast `Black.*` and `Bachelier` price/Greek APIs have a separate, checked-corpus
assurance scope. They do not perform runtime output certification. Each fast Greek now returns a finite value or an explicit numerical failure;
see [the result contract](docs/finite-greek-results.md). Distinct-group planner
compilation uses hash-table insertion with checked counts; see the
[scaling measurements](docs/results-planner-compilation.md).

The project retains independently generated references, analytical error bounds,
exact-rational checks, negative type tests, mutation witnesses, and a determinism
digest. These establish different facts; passing finite corpora is not a proof
over every admitted input. See the
[current assurance scope](docs/error-analysis.md#certification-status-and-remaining-proof-obligations).

## Documentation and contributions

- [Documentation guide](docs/README.md): current contracts, derivations, and historical evidence.
- [Public API](lib/morphiq_risk.mli), [model definitions](docs/model-contracts.md), and [production acceptance](docs/production-boundary-design.md).
- [Scenario contract](docs/scenario-planner.md) and [measured planner results](docs/results-planner.md).
- [Security reporting](SECURITY.md): privately report vulnerabilities.
- [Experimental qualification](docs/experimental-baseline.md): scope, evidence and remaining limitations.
- [Contributing](CONTRIBUTING.md): setup, checks, numerical changes, and pull requests.
- [Compatibility policy](docs/stability.md) and [changelog](CHANGELOG.md).
- [Issues](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues): bug reports and proposed work.

## Licensing

Original project contributions are licensed under [Apache-2.0](LICENSE).
Copyright 2026 Prophetizo LLC, doing business as MorphIQ Labs, and contributors.
Third-party material retains its own terms; see [NOTICE](NOTICE) and
[third-party notices and provenance status](THIRD_PARTY_NOTICES.md). The [current-source audit](docs/opensource-closeout.md) records the AS241,
CALERF and QD replacements and retained permissive notices. Historical versions
retain their unresolved terms; replacement does not relicense old commits.

Research papers retain their authors' and publishers' rights and are linked
from the [bibliography](docs/research/README.md), rather than bundled in the
source tree. This license applies to this project only; it does not license
FerroRisk or other MorphIQ Labs repositories, or grant trademark rights.
