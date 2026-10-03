# Scenario planning contract (version 1)

Epic #23 supplies the scenario planner. This feature extends orchestration of
the existing European scalar contract; it does not change prices, Greeks, IV
acceptance, or institutional deployment approval.

## Financial meaning (#24)

The first convention is the Epic's recommended **forward valuation-date roll
with fixed instrument expiries and frozen market inputs**. The owner's autonomy
instruction permits this implementation choice; it is not a claim of a new
institutional model-validation signature. Dates are integral civil-day ordinals
in [-1,000,000,000, 1,000,000,000], and scenario offsets are nonnegative civil-day
counts up to 1,000,000,000. Callers own conversion from calendar dates; no
business-day calendar or intraday convention is implied. Actual/365 Fixed and
Actual/360 are separate explicit choices. Remaining maturity is the exact integer
day difference divided once in binary64 by 365 or 360. That rounded year fraction
becomes the exact scalar input. Greeks retain the scalar model's per-calendar-day
unit (-d/dT / 365), even when the date convention is Actual/360.

For base day 0 and expiry 90, offsets 0, 7, 30 give 90/365, 83/365,
60/365 under Actual/365 Fixed. Offset 90 evaluates certified expiry prices;
smooth Greeks retain Production's explicit expiry exclusion, including cases
where a legacy boundary derivative exists. Offset 91 returns `Post_expiry`,
with no invented settlement price or silently clamped maturity. Expiry price
and the smooth-Greek capability are distinct outcomes.

Each market factor is explicitly spot/lognormal, forward/lognormal, or
forward/normal. Instrument models must bind to the corresponding factor. BSM
holds dividend yield fixed; forward models hold their contractual forward
coordinate; displacement, strike and rate remain instrument terms. There is
no implicit spot-to-forward shock conversion. Named volatility axes distinguish
normal from lognormal units. Unsupported bindings are compile errors.

Each shock is an absolute replacement, additive change or relative multiplier.
Every scenario starts independently from the frozen base snapshot. Duplicate
shocks to one factor/coordinate are rejected, so there is no hidden composition
order. Addition and multiplication round once in binary64 using the project's
noncontraction boundary. The resulting words define the pricing request; the
planner does not promise an exact-real shock transformation. Nonfinite/negative
shocked values reach scalar/volatility admission and remain per-item failures.
A negative normal forward is valid. A negative displaced forward may be valid
if its exact shifted coordinates pass existing admission; the shift is never
applied/rounded in the planner.

Paired scenarios enumerate explicit tuples in supplied order. Cartesian axes
vary with the last axis fastest. A level array includes every supplied endpoint;
an indexed range has explicit first/step/count, no inferred end. Value zero
preserves `first` exactly (including signed zero); other values use IEEE
`fma(float(index), step, first)`. Indices are at most 2^53-1, so their float
conversion is exact. The finite end check bounds this monotone real affine
sequence; no repeated additions accumulate drift. An empty axis gives zero
scenarios; no axes give one base scenario. Duplicate time axes are rejected.

Outputs are scenario valuations and typed analytic sensitivities. There is no
cross-time P&L, baseline-difference, settlement, financing or currency-conversion
API. Remaining-maturity research sweeps, quote scenarios/IV jobs, full-cube
materialization and durable resume are explicitly outside this planner version.
The independent `Batch` API does support externally supplied IV quotes and
retains every `Iv.t` class; it never manufactures quotes by inverting its own
scenario prices.

## Compilation and batch ownership (#20/#25)

`Planner.compile` freezes array inputs, validates identities/bindings/output
coordinates and limits, records exact words, and produces an abstract plan.
Immutable records/lists/strings may be shared; callers must not concurrently
mutate an array while a constructor copies it. Unsafe string/representation
mutation is outside OCaml's typed contract. No caller array alias is retained.
Plans can be independently executed more than once with new output destinations.

Compilation is structural, not a numerical certificate of all stressed cells.
Each cell uses `Batch.evaluate`, which delegates to the existing Production
model admission and typed evaluation. There is no second admission owner,
fast-price fallback, fitted tolerance, cache or algebraic rewrite. The caller
sets each output's typed absolute limit. Requests preserve model identity,
volatility coordinate, side and input words; each output preserves its quantity
GADT and typed certificate or explicit error. Homogeneous batch arrays return
fresh arrays of exactly the same length, including zero. No output-buffer API
or aliasing contract is hidden in this version.

The initial layout is an array of immutable position records, a copied factor
array, and an instrument-to-factor index. This admits heterogeneous instruments
and outcomes without storing a full cube or inventing vectorized kernels.
There is no shared mutable cache. Reuse is limited to frozen specifications,
factor bindings, output lists and bucket keys; each scalar calculation includes
all its own original inputs. Any future cache key must include model/terms,
side, all coordinates, time, snapshot identity, quantity and numerical policy.

Cardinality arithmetic checks every product and sum before allocation or use.
Limits cover instruments, scenarios, calculations, logical tile rows, workers,
buffered result slots and distinct aggregation groups. Raw value/error volume
is 16 bytes per calculation and is explicitly a **lower bound**, excluding
object, identity, outcome and encoding overhead. Result-slot bounds also count
rows with no requested outputs. `explain` supplies these counts, the policy,
convention version and content identity. It is not a hard process-RSS estimator:
OCaml GC heap, scalar arithmetic scratch, input records and compiler/runtime
memory are additional. Full materialization is not an available operation.

The canonical plan encoding uses length-prefixed strings, exact float hex words,
explicit variant tags, counts, ordered inputs/axes, limits and output policy.
BLAKE2b-256 identifies that encoding; no process-local hash participates. The
manifest adds OCaml version and word size. A replay archive must also retain
original input data, source/executable identity, compiler flags and dependencies.
The manifest is an identity record, not a serialized reconstruction of the book.
Stable tiles carry plan identity, scenario index and contiguous instrument extent.

## Aggregation proof and completeness (#26)

Aggregation buckets retain currency, market factor, explicit rate factor, model (including BSM carry or
contractual displacement), volatility coordinate and quantity/unit. This is
conservative: financially distinct factors or models are never netted implicitly.
The caller names the rate factor: rho means a parallel unit change to the flat
rate inputs of instruments sharing that factor. Instruments with distinct rate
factors are never implicitly combined, even when their current rates agree.
One named market factor cannot be bound to instruments in conflicting
denominations. Different currencies require distinct factor bindings; an
implicit FX transformation is never inferred.
Bucket comparison treats positive and negative zero in BSM dividend yield or
contractual displacement as equal: those parameterizations describe the same
real model. Summary metadata retains a representative input key, without
canonicalizing its zero sign. Plan identity still encodes all original input
bits, including signed zeros.
Quantities are explicit position multipliers. Nothing supplies an implicit
contract multiplier, FX conversion, or common-volatility risk factor.

For scalar result x_i with certified absolute radius e_i and exact binary64
position w_i, the real weighted contribution belongs to

    w_i [x_i-e_i, x_i+e_i].

The implementation constructs that interval with `Enclosure.exact` and
`add_error`, multiplies by the exact weight with `mul_float`, and adds in
ascending original instrument order. Induction on the existing enclosure
invariant gives containment of the sum of accepted contributions. Multiplication
includes the scalar uncertainty |w_i| e_i and its own arithmetic residual;
addition includes previous uncertainty and its own residual. These are the
same finite-exponent, residual and underflow-quantum rules derived in
[runtime-enclosures.md](runtime-enclosures.md), not a newly fitted gamma_n
allowance or an assumption of associative binary64 addition. Cancellation is
covered by absolute error. Scalar underflow, weighted underflow and summation
underflow remain in the outward radius. Intermediate overflow or unresolvable
arithmetic makes the aggregate unavailable; a later cancellation does not
retroactively justify an overflowing intermediate.

The reported centre is the retained high word and the radius is
`Enclosure.error_of_float`; nonfinite results are never served. No aggregate
accuracy budget is inferred from scalar limits. The consumer must assess the
reported aggregate radius against its economic/numerical policy.

A summary has successful/failed counts and an optional **successful subset**
enclosure. It is a complete total only when every requested leaf in that bucket
succeeded and aggregate arithmetic resolved. Even a failed zero-weight item is
retained and prevents completeness. Stream mode emits every row. Aggregate-only
mode emits every row with failures, plus all completed scenario summaries;
failures retain stable scenario/instrument/quantity identity. An interrupted
scenario has no complete summary. An empty portfolio emits only completion.

## Scheduler and output transaction (#21)

Logical tile order is scenario-major, then original instrument order. The
upstream OCaml executor uses bounded fork/join waves of at most the requested
worker count, within the compiled maximum. A domain reads a frozen plan and
constructs its private result array; its only shared mutable control is the
coordinator's separate atomic cancellation flag. There are no worker callbacks
or shared caches. All handles are joined, including after spawn failure, before
callbacks or return. The coordinator owns aggregate mutation and calls the sink
serially in logical order. Changing wave size or tile boundaries cannot change
leaf/reduction order. This is an ownership/synchronization design, **not** an
OxCaml mode-checking proof.

At most one wave is retained. A slow first tile or slow sink prevents dispatch
of the next wave. Cancellation is checked between waves and before each committed
row; running scalar evaluations finish within their existing bounded work.
Cancellation latency therefore depends on the selected tile size and scalar
cost. No unsafe asynchronous worker interruption is used. Domain creation per
wave is an intentionally simple baseline; its cost is measured rather than
hidden in a persistent scheduler claim.

The sink returns success only after accepting its event. An error or exception
stops further output; a sink that writes partially and then fails may have an
uncommitted fragment. A final `Finished` event reports Complete, Cancelled, or
Worker_failure when the sink remains usable. A broken sink cannot be promised
that marker. Consumers must require Complete before treating a run as complete.
Rows committed before a later summary/sink failure remain a prefix; partial
output must be discarded or separately diagnosed. The planner never retries,
resumes, or appends a second execution to an existing sink automatically.
Exactly-once durable delivery across process failure is not claimed.

The supported reproducibility scope is identical source/toolchain/platform and
exact frozen inputs, independent of worker count and physical completion order.
Cross-platform evidence is measured separately; ordinary upstream OCaml does
not prove race freedom, deterministic arithmetic on untested hardware, or
financial correctness.

## Primary references

- [OCaml 5.3 Domain API](https://ocaml.org/manual/5.3/api/Domain.html): spawn,
  join, exceptions, and domain lifecycle.
- [OCaml 5.3 parallel programming](https://ocaml.org/manual/5.3/parallelism.html):
  data races and synchronization obligations.
- [OxCaml canonical fork/join tutorial](https://oxcaml.org/documentation/tutorials/intro-to-parallelism-part-1/):
  mode-checked worker boundaries; the separate experiment must actually compile
  its positive and negative cases before making that claim.
- Existing model, numerical backend and runtime enclosure contracts remain the
  authority for arithmetic. The planner introduces no new pricing formula.

## Runnable job

`opam exec --switch=morphiq-risk-ml -- dune exec examples/scenario_job.exe -- --workers 2`
compiles a frozen BSM position across three spot levels and three valuation
rolls, explains its bounded plan, and streams nine certified scenario totals.
Run with `--workers 1` or `4` to change only physical execution. The source in
[examples/scenario_job.ml](../examples/scenario_job.ml) shows the public API,
including explicit rate-factor identity and numerical limits. The printed
values are scenario valuations, not economic P&L.
