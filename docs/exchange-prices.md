# Certified scalar exchange prices

`Morphiq_risk.Exchange` prices a European exchange of one unit of the deliver
asset for one unit of the receive asset, both in the same currency. Its constant
correlated lognormal model and yield extension follow the
[original-input contract](first-model-extension.md). Common interest rate
cancels; reversing exchange swaps both complete asset records.

```ocaml
open Morphiq_risk

let get = function Ok x -> x | Error _ -> failwith "invalid example input"
let receive = Exchange.{ spot = 100.; dividend_yield = 0.01;
                         volatility = get (Vol.lognormal 0.2) }
let deliver = Exchange.{ spot = 95.; dividend_yield = 0.02;
                         volatility = get (Vol.lognormal 0.3) }
let admitted = get (Exchange.admit ~receive ~deliver ~time_to_expiry:1.
                     ~correlation:(get (Exchange.correlation 0.5)))
let result = Exchange.price admitted ~max_error:1e-9
```

The executable example `dune exec examples/exchange_price.exe` handles every
price outcome. A successful result has a finite value and finite nonnegative
outward absolute error, in currency units, at most the requested limit. This
is an error certificate, not an additional nearest-even guarantee. A zero
limit requires zero certificate radius. Caller market/model uncertainty is
outside the numerical radius.

Correlation construction owns finite [-1,1] validation. Admission owns both
finite nonnegative spots, both finite yields and finite nonnegative maturity;
volatility uses the existing typed lognormal constructor. Validation occurs
before expiry/zero-asset selection. The local input-error type identifies the
leg and field without changing existing exhaustive errors. Abstract admissions,
correlations and private certificates cannot be forged through this API.

`Invalid_accuracy` rejects nonfinite/negative limits. `Numerical_failure`
means arithmetic could not produce a finite enclosure; `Accuracy_exceeded`
means a finite enclosure missed the requested limit. Neither contains a
fallback. Admission is mathematical, not an availability promise. The initial
implementation uses one full bounded enclosure attempt; discount arguments
must satisfy the existing exp owner's |q*T|<=256 domain. Extreme scaling,
subnormal restoration, uncertain positive square roots and overflow can fail.
Equal assets/yields with exactly zero covariance return exact zero; expiry
uses the original spot difference. Rounded zero variance never selects a
boundary. See the [method and preconditions](evidence/exchange-implementation/method.md).

No fast-price, Greek, inverse-parameter, Batch, Scenario or Planner API is
included. Existing portfolio specifications lack two separately shocked
underlyings/yields and correlation. Adding such adapters requires their own
financial and aggregation contracts. Existing one-asset runtime owners and
error types are unchanged; this is an additive minor API change. No version
bump, release or institutional approval follows automatically.

## Focused implementation evidence

The [frozen protocol](evidence/exchange-implementation/protocol.md) retains all
66 original-word requests and the initial oracle limitation discovered while
checking tiny currency scales. The corrected independent references normalize
payoff quadrature and refine the tail with precision. Both routes use original
inputs: exact rational covariance with Arb closed form, and rigorous positive
payoff integration with strike-strip and Mills tail bounds. Exact boundaries
use independent identities/discount intervals. No production kernel is imported
into either reference; public builds need no private papers or Python Arb.

The final focused run serves 47 certificates: **46 contain both complete
independent intervals**, and one extreme-volatility result is **unadjudicated**
because the quadrature route reaches its capability guard. Ten requests fail
explicitly for arithmetic or requested accuracy, seven fail input construction
or admission, and two reject the accuracy limit. All three mandatory ordinary
prices and eight exact boundary controls succeed. These are finite-corpus
observations; the unadjudicated row is not an accuracy pass. Full qualification
of the extension remains [#61](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/61).

Before runtime changes, QuantLib `79f08f66bc7f42ab228f37d15ee0cb4f2d920e0c`
was built and executed. The [build record](evidence/exchange-implementation/quantlib-build.json)
pins compiler/configuration/runner/library hashes. The comparator uses
2025-01-01, Actual/360 on both processes, whole-day exact maturities, unit
quantities, flat continuous yields/rates and constant vols. Three common rates
(0, +0.05, -0.05) expose binary64 rate-cancellation variation. Across 198 runs:
147 finite, 24 nonfinite, 27 excluded by input/date mapping. Same-date expiry
uses QuantLib Instrument's expired NPV=0 convention; it is explicitly distinct
from this API's expiry payoff. Near-singular covariance uses QuantLib's own
rounded subtraction. The [per-case comparison](evidence/exchange-implementation/quantlib-comparison.json)
retains discrepancies and exclusions rather than treating that comparator as
mathematical ground truth or silently adopting its boundary behavior.

Rebuild the optional comparator out of tree:

```sh
cmake -S /path/to/pinned/QuantLib -B /tmp/exchange-ql -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=17 \
  -DCMAKE_CXX_FLAGS=-ffp-contract=off \
  -DQL_BUILD_EXAMPLES=OFF -DQL_BUILD_TEST_SUITE=OFF
cmake --build /tmp/exchange-ql -j 2
clang++ -std=c++17 -O3 -ffp-contract=off \
  -I/tmp/exchange-ql -I/path/to/pinned/QuantLib -I/path/to/boost/include \
  scripts/exchange_quantlib.cpp -L/tmp/exchange-ql/ql -lQuantLib \
  -Wl,-rpath,/tmp/exchange-ql/ql -o /tmp/exchange-quantlib
```

The runner reads case ID followed by the nine hex words in corpus field order;
it records the actual year fraction for every evaluated row. QuantLib is an
optional comparator only; no QuantLib runtime source or coefficients were
copied into Exchange. Project derivations and original code retain Apache-2.0.
