# Numerical execution and backend contract

This contract owns the evaluation semantics of the European pricing slice.
The real models remain those in [model-contracts.md](model-contracts.md).
Changing an execution strategy does not change the meaning of its inputs,
volatility coordinates, quotes, Greeks or failures.

## Required arithmetic environment

The supported baseline is OCaml 5.3.0 with Flambda, the locked dependencies,
the library's `-O3` build, and the three platform jobs in `ci.yml`. Those jobs
are Linux x86-64, Linux arm64 and macOS arm64. A different compiler, target,
backend or dependency version is a candidate requiring conformance evidence;
being able to compile the source is insufficient.

- Binary64 basic arithmetic and square root round to nearest, ties to even.
  Gradual underflow is required. Flush-to-zero, denormals-are-zero and changes
  to the floating-point rounding mode are outside the contract.
- Each source multiplication rounds separately through `Morphiq_fp.( *. )`.
  Only explicit `Float.fma` calls are fused. The FFI multiplication stub
  compiles with contraction disabled. Double-word residual algorithms depend
  on the stated ordering and on normalized input words.
- No reassociation, reciprocal replacement, approximate square root,
  fast-math, finite-only assumptions or signed-zero elimination is permitted
  merely because a real-number identity holds.
- Constants are the stored binary64 words. Recomputing a decimal coefficient,
  importing another library's coefficient table, or changing polynomial
  grouping is a numerical change needing a new derivation and evidence.
- Elementary and normal functions are the project implementations. Host libm
  or vector approximations are not equivalent substitutes by declaration.
  Their full required domains and error bounds must be established first.
- Invalid inputs, payoff kinks, mathematical IV classifications and numerical
  failures retain their distinctions. A backend cannot replace a failed IV
  solve with a last iterate, a zero, or a mathematical no-root classification.

The embedding application must preserve this arithmetic environment on every
calling thread/domain, including across foreign calls. A startup probe detects
some violations; it does not prove that foreign code cannot change the state
later. Test evidence is scoped to the recorded environment and inputs.

## Three independent conformance questions

| Question | Requirement and witness |
| --- | --- |
| Does it implement the same financial quantity? | Same exact original inputs, carry/shift rules, coordinates, Greek units, expiry/kink semantics and failure meanings. Domain and type tests exercise this contract. |
| Is its numerical error justified? | Independent high-precision references and analytical/per-input certificates over the supported domain, including tails, cancellation, exponent limits and branch boundaries. A new operation graph needs matching bounds; passing the old scalar replay alone is insufficient. |
| Does it reproduce served bits? | The standard backend must match the committed determinism digest on all supported platforms. An intentional changed-bit backend needs a compatibility decision and per-row numerical evidence before a new digest is accepted. |

A changed digest is not a numerical mutation kill. Conversely, identical
digests on a finite corpus do not establish a universal error bound or correct
exception handling outside that corpus. Unresolved oracle rows stay unresolved
and must be reported, not silently counted as successful comparisons.

## Optimization decisions

| Transformation | Decision |
| --- | --- |
| Reuse an identical immutable computation | Allowed when every input, model convention, side, unit and numerical option is identical; preserve the same arithmetic result and failure. Cache keys must include all dependencies. |
| Hoist common work across portfolio items/scenarios | Requires a demonstrated dependency identity, frozen snapshots and safe ownership; planner scheduling cannot change reduction order or hide partial results. |
| Reassociate sums/products; change normalization, scaling or branch thresholds | Requires an operation-level derivation, finite-exponent/precondition audit, independent references, compatibility assessment and measured performance. |
| Fuse a multiply/add; vectorize a polynomial; approximate reciprocal/transcendentals | Requires new error analysis and backend conformance. No blanket permission from `-O3`, SIMD availability or real-number algebra. |
| Replace two-word quantities by their high words | Unsupported unless the specific discarded contribution is bounded in the resulting quantity and its required domain. |
| Enable fast-math, FTZ/DAZ or assume all intermediates finite | Unsupported under this contract. A separately scoped contract and implementation would be required. |
| Eliminate validation/failure branches as "unreachable" | Requires a proof from enforced admission and all subsequent operations. Tests of ordinary market inputs do not prove unreachability. |

Fix the numerical and economic acceptance requirements before scoring. A
performance result cannot justify widening a budget after a discrepancy is
observed. Report allocation/GC, packing, dispatch and end-to-end costs as well
as scalar arithmetic throughput. A faster kernel can still be a slower job.

## Candidate assessment procedure

1. Record the exact base/candidate revisions, compiler and dependency versions,
   build flags, hardware/OS, intended domain and changed operation graph.
2. Classify the transformation above. Write its mathematical and finite-
   arithmetic justification before measuring reference discrepancies.
3. Run build/format and the complete ordinary suite locally in the candidate
   environment. Preserve logs and fixture provenance. The runtime arithmetic
   probe, unit rejection, failure controls, exact-input references,
   certificates and replay digest answer distinct questions.
4. Run affected named mutations, requiring a clean baseline, a successful
   mutated build and the designated numerical/precondition witness. Keep the
   seven core mutations in default CI; full mutation assurance stays manual
   or scheduled, including release acceptance.
5. Investigate every new discrepancy against independent precision-refined
   calculations, accounting for model and input-conversion differences. Never
   use the current scalar implementation as the sole correctness oracle.
6. Run controlled repeated performance comparisons and retain spread and host
   limitations. Record a go/no-go decision tied to the evidence, refresh the
   model-risk acceptance dossier, and apply the stability policy.

The reusable harness is the ordinary Dune test graph plus the three-platform
CI matrix. A backend that changes operations must supply a corresponding
certificate/replay implementation and run the same model fixtures and failure
controls; turning off a mismatching certificate is not conformance. There is
no pluggable alternate pricing backend today. This contract does not invent
one merely to satisfy an architectural abstraction.

## Automatic differentiation

An AD backend must differentiate the intended real model in the documented
coordinate and units. Differentiating the rounded approximation or its branch
selection can give a different quantity. Expiry and zero-variance kinks require
the same per-Greek refusal; an arbitrary subgradient is not the existing Greek.
Near cancelling and mixed/third-order derivatives, require independent
differentiation of the high-precision model and the analytical certificates,
not only agreement with the scalar closed form. A branch or threshold change
needs a sensitivity audit on both sides and at the boundary.

## Foreign and generated backends

Any FFI or generated-code proposal must specify versioned calling and data
layout conventions, model identity, units, exact displaced inputs, ownership,
lifetime, alignment, thread/domain use, exceptions and result/failure encoding.
No foreign function may retain borrowed scratch data beyond its lifetime or
mutate shared inputs. NaN payloads are not a replacement for the public failure
variant. Round-trip packing tests, deliberate failure controls and measured
packing/call overhead are required. OxCaml mode checking would cover only its
checked boundaries; foreign code remains an explicitly audited trust boundary.

## Worked assessment: implicit contraction

For `a = 1 + 2^-27`, `b = 1 - 2^-27`, the exact product is `1 - 2^-54`.
Separate binary64 multiplication rounds it to 1, so subtracting 1 gives zero.
A fused multiply-add gives `-2^-54`. Both are correctly rounded operations,
but they implement different evaluation graphs. Residual extraction and the
published double-word algorithms select specific graphs deliberately.

The existing audit found platform-dependent implicit contraction and installed
the `Morphiq_fp` multiplication boundary; see [determinism.md](determinism.md).
The runtime conformance test retains this exact witness, explicit FMA behavior,
ties-to-even and subnormal arithmetic. The test demonstrates the mechanism;
the ordinary numerical suite and platform digest check its consequences.

**Decision:** retain the multiplication boundary and explicit `Float.fma`.
Reject removal based only on benchmark speed or algebraic equivalence. A
proposed alternative must establish the same evaluation graph on every
supported target or derive and qualify the changed graph. This decision does
not claim formal verification of the compiler or of all foreign arithmetic.
