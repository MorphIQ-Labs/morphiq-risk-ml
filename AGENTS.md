# Repository Guidelines

**Correctness and defensibility are the highest-priority features of this project.**
Performance and clean architecture are first-class requirements, but neither
delivery speed nor optimization justifies a less correct numerical result.
State the contract, derive the method, enforce its preconditions, and retain
reproducible evidence. A passing test suite is evidence over its exercised
inputs, not a universal proof.

This file is the repository's engineering contract and single source of truth
for agent instructions. `CLAUDE.md` contains only `@AGENTS.md`.
The policies are adapted from `ai-program/AGENTS.md` and the root and engine
guides in `ferro-risk`, specialized for this OCaml project. Their Rust commands,
GitLab workflows and release automation are not this repository's tooling.
Explicit user instructions take precedence; do not turn routine implementation
choices into additional approval requirements.

## Purpose and Architecture

`morphiq-risk-ml` is an independent OCaml implementation of the exact European
option family: BSM, Black-76, displaced Black and Bachelier, with prices,
implied volatility and ten analytic Greeks. It works from first principles,
research and canonical implementations; it is not a line-by-line Rust port.
FerroRisk is an optional independent comparison, not a runtime dependency or
the definition of correctness.

Read the [documentation guide](docs/README.md), [model contracts](docs/model-contracts.md),
[error analysis](docs/error-analysis.md), [oracle methodology](docs/oracles.md),
[determinism](docs/determinism.md) and [stability](docs/stability.md) before
changing behavior. Consult the relevant `docs/results-*.md` evidence as well;
historical results must not be mistaken for current acceptance rules.
Compiler, arithmetic or backend work additionally follows the
[numerical backend contract](docs/numerical-backend-contract.md).

- `lib/fp/` owns the binary64 multiplication boundary that prevents implicit
  multiply-add contraction; explicit fused operations use `Float.fma`.
- Numerical primitives, elementary/normal functions and normalized pricing
  kernels in `lib/` feed the model implementations. They must not depend on
  portfolio orchestration, transport or application policy.
- `Black.Make` shares the lognormal kernel across carry/shift choices;
  `Bachelier` owns the normal model. Model-specific abstract admission types
  and volatility coordinates enforce structural separation.
- `Exchange` owns certified scalar two-asset European exchange prices, with
  typed correlation, original-input covariance and private currency certificates.
  Read [its contract and limits](docs/exchange-prices.md); Greeks, inverse
  parameters and portfolio adapters are outside this additive API.
- `Production` owns per-request runtime numerical acceptance for prices and smooth Greeks, with explicit typed absolute limits and private certificates. Read [its supported capability](docs/production-boundary-design.md); mathematical admission is not output acceptance, and the adapter is not institutional sign-off.
- `lib/morphiq_risk.mli` defines the primary public interface.
  `Morphiq_risk.Internal` is an unstable research/testing surface, not an
  integration API. `.mli` abstraction and Dune library dependencies enforce
  existing boundaries; there is no separate architecture-lint gate today.
- `oracle/` owns precision-refined independent calculations; `test/` owns
  scoring, certificates and regressions. Production code must not import them.
  Zarith and the generated exact-rational replay are test-only.

Current runtime flow: original inputs -> model admission -> typed volatility
and admitted model -> shared kernel -> price, IV outcome or per-Greek result.
OCaml/Dune/opam own language, compilation and packaging; this repository owns
financial semantics, numerical algorithms and their evidence. Generic upstream
fixes should be contributed to their owner and consumed at a recorded version.

## Project Structure

- `lib/`: OCaml implementation and signatures; `lib/fp/`: small C primitive.
- `test/`: reference, consistency, property, determinism and regression tests;
  `test/types/`: compile-failure witnesses for API constraints.
- `oracle/`: Python generators, analytical bound checks and `MANIFEST`;
  `oracle/fixtures/*.txt.gz`: committed fixtures. Decompressed fixtures are
  generated and ignored.
- `scripts/mutation/`: curated mechanisms, core selection and selection tests.
- `bench/bench.ml`: scalar throughput harness; timings are host-dependent.
- `docs/`: contracts, derivations and evidence; `docs/research/`: bibliography,
  provenance manifest, canonical filenames and SHA-256 checksums. Downloaded
  PDFs may be retained locally but are ignored and are not distributed.
- `.github/workflows/`: GitHub Actions; `dune-project`: package/dependencies;
  `morphiq_risk_ml.opam.locked`: locked dependencies; `.ocamlformat`: formatter.

The surrounding `MorphIQ-Labs` directory is not a git repository. Run git and
build commands here; never assume a workspace-wide build or change sibling
repositories as an incidental side effect.

## Build, Test, and Development Commands

Use upstream OCaml **5.3.0 with Flambda**, as CI does, and the pinned formatter
**0.27.0**. The numerical library uses `-O3`. Keep this compiler for development
and CI; OxCaml is an experiment, not the current toolchain. Do not switch
compilers merely to shorten compilation without measuring a bottleneck.

Run from the repository root after activating the project opam switch:

```sh
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
eval "$(opam env --switch=morphiq-risk-ml)"
opam install . --deps-only --with-test --locked
opam install ocamlformat.0.27.0
ocamlopt -config-var flambda                 # must report true
dune build @install                         # build public package
dune build @fmt                             # check formatting
dune test                                   # complete ordinary suite
dune exec test/consistency.exe              # focused cross-quantity check
dune build bench/bench.exe                  # compile benchmark
dune exec --release bench/bench.exe         # local performance evidence
```

Create the switch only if it does not already exist. For an existing switch,
`opam exec --switch=morphiq-risk-ml -- dune ...` avoids relying on shell state.
Python 3's standard library is needed for ordinary analytical/manifest checks.
Oracle regeneration additionally needs the pinned mpmath environment described
in [docs/oracles.md](docs/oracles.md):

```sh
oracle/build.sh                            # regenerate all reference fixtures
scripts/ferro_crosscheck.sh                 # optional external comparison
dune exec scripts/mutation/mutation.exe -- --core
dune exec scripts/mutation/mutation.exe -- quotient-remainder
dune exec scripts/mutation/mutation.exe -- --list
dune exec scripts/mutation/mutation.exe     # full catalog; optional/manual
```

For numerical, API, compiler or dependency changes, run build, format and the
ordinary suite locally before pushing, plus affected reference/mutation
witnesses. For documentation-only changes, check links, commands and diff
integrity and run build/format; numerical mutations need not be rerun locally.
Hot-path changes carry controlled before/after measurements. Do not repeatedly
rerun broad assurance after it passes unless new changes or concerns justify it.

### CI and mutation policy

[ci.yml](.github/workflows/ci.yml) runs on pull requests and pushes to `main`:

- `test (ubuntu-24.04)`, `test (ubuntu-24.04-arm)` and `test (macos-15)` build
  and run the full ordinary suite in development and release profiles, including oracle/certificate checks,
  properties, type rejection, fixture provenance and the determinism digest.
- `format` checks the pinned ocamlformat configuration.
- `mutation` runs **only the seven reviewed core mutants**. The job name does
  not mean the full catalog runs on pull requests.

[mutation-full.yml](.github/workflows/mutation-full.yml) runs the full catalog
on manual dispatch and Mondays at 06:00 UTC on the default branch, retaining
its log. It has no PR/push trigger. Preserve this separation; adding assurance
must not silently restore the full mutation workload to default CI. Scheduling
requires the workflow to be present on the default branch.

`candidate.yml` is a separate manual lane for one immutable commit already on
main: three-platform source-artifact installation/native/bytecode validation,
ordinary checks and a full mutation job. It neither publishes nor tags a release.
Its full catalog does not change the seven-mutant default CI policy.

Follow [docs/mutation-policy.md](docs/mutation-policy.md). Changes outside the
core require the affected named mutants locally; broader campaigns remain
explicit/manual or scheduled. A kill requires a clean baseline, a successful
mutated build and the designated numerical/precondition witness failing.
Compiler errors, missing tests, harness failures and changed replay bits do
not establish kills. Mutation runs disable replay-identity checks; ordinary
tests retain them. Surviving probes remain documented limitations, not proofs
that no discriminating test can exist.

The normal Dune development build treats enabled warnings as errors; the
mutation profile deliberately differs. No separate OCaml lint tool, pre-commit
hook, performance threshold gate, fuzz campaign or proof-assistant CI job is
configured here. Do not report such gates as passing or borrow those claims
from FerroRisk. Validate workflow changes locally with `actionlint`, and
exercise changed gate scripts and their failure controls before pushing them.

## Numerical Contracts and Assurance

1. **Define the quantity before choosing the algorithm.** Specify domain,
   units, conventions, preconditions, output guarantees and failure outcomes.
   Price, IV and Greeks must describe the same real model. A binary64 input is
   the exact real number it represents; intermediates are not silently part of
   the model. Displaced sums remain exact as required by the model contract.
2. **Start with first principles and primary sources.** Read original algorithm
   boxes, theorem assumptions, corrections and canonical source implementations
   at recorded versions. Explain deviations. Normal-intermediate or
   unbounded-exponent theorems do not automatically cover subnormals, scaling,
   overflow, arbitrary low words or every production call site.
3. **Establish references before changing numerics.** Build and execute the
   applicable canonical implementation at a recorded revision; retain its
   baseline and independently refine from original inputs.
   Identify absent counterparts and differing conventions. Do not infer that
   agreement with FerroRisk, QuantLib or another binary64 library proves
   accuracy; this repository does not yet have FerroRisk's mandatory QuantLib
   comparison gate. Document discrepancies per case, including input-conversion
   effects and unresolved differences, rather than only aggregate improvement.
4. **Derive bounds before scoring.** Separate analytical truncation error,
   rounding, conditioning, input transformation and reference uncertainty.
   Measured envelopes are regression evidence, not derived guarantees. Never
   tune a tolerance or threshold until tests or mutants pass, or widen an
   accuracy budget to absorb a regression. A corrected derivation needs its
   own evidence and compatibility assessment.
5. **Treat the oracle as fallible.** Precision agreement alone can share a
   cancellation or termination defect. Preserve independent formulations,
   extra bits, precision refinement and unresolved outcomes. Never drop hard
   rows or count an unresolved reference as a successful accuracy comparison.
   Regenerate fixtures with their transitive provenance; never hand-edit a
   fixture or hash to conceal a generator/implementation mismatch.
6. **Separate scopes of assurance.** Published theorems, project derivations,
   exact-rational checks, per-input replay certificates, empirical envelopes
   and cross-platform digests establish different facts. The
   [certification status](docs/error-analysis.md#certification-status-and-remaining-proof-obligations)
   is authoritative: checked certificate domains are not every finite input
   admitted by the API; IV now enforces runtime boundary and rounding-cell enclosures. Test certificates
   are not runtime certificates or formal verification of the compiler.
7. **Preserve arithmetic semantics.** Keep `Morphiq_fp` multiplication and
   explicit `Float.fma` usage. Do not introduce implicit contraction,
   reassociation, fast-math, host `erf`/transcendental substitutions or new SIMD
   approximations without an operation-level analysis and independent checks.
   Portability evidence covers the tested platforms, not all architectures.

The IV contract work is tracked in
[Bug #14](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/14). Public positive roots now require the [exact-model rounding certificate](docs/certified-iv.md),
with explicit uncertainty failures and bounded work. Do not claim that a rounded-evaluator bracket is an
exact-model enclosure or that an iteration cap proves convergence. Distinguish invalid input,
mathematical non-existence, insufficient representability and numerical
failure; never turn a failed computation into a plausible successful value.
Missing reference coverage is not itself mathematical invalidity. An offered
production capability restriction must be documented as such.

### Research references and preservation

Research papers are durable assets. Preserve acquired originals and notices in
the private [research library](https://github.com/MorphIQ-Labs/research-library),
subject to their terms; follow its README.md, RIGHTS.md and AGENTS.md. Use
`YYYY-first-author-short-title[-version].pdf` with the filename stem as a stable
ID. Record exact versions, original sources, actual acquisition routes/dates,
SHA-256, byte counts, consuming projects and document-specific rights status.
Keep acquisition snapshots unchanged and unavailable papers explicit.

This public project retains its bibliography, source links, version hashes,
derivations, contracts, tests, fixtures, generators and numerical evidence.
Builds and CI must not depend on private-library access. Inspect compressed archives, source patches and embedded payloads as source material during distribution audits; a switch export can contain third-party code, not just dependency metadata. Local PDF copies are
optional and ignored; do not commit them without recorded redistribution
permission. Public availability or a related code license is not such evidence;
private storage does not itself authorize broader team sharing. Keep publication
rights separate from implementation provenance and the project's Apache license.

Verify preservation and matching destination hashes before removing tracked
research copies; update public references together. Untracking does not erase
Git history, existing clones or archives. Do not rewrite history as incidental
cleanup. See the [bibliography](docs/research/README.md) for the migration record.

## Invariants, Ownership, and Review

Choose enforcement in this order: unrepresentable by construction; checked
inside the owning component; only then a tested convention. Name the owner
and executable witness. Types enforce declared invariants, not the correctness
or completeness of the requirements themselves.

- Preserve model-specific admission, normal/lognormal volatility coordinates
  and Greek units. Validate original inputs at their owner and pass typed
  evidence downstream. Do not duplicate admission or erase meaning to raw
  floats across layers without an explicit boundary contract.
- Test behavior and mathematical properties, not source text or statement
  order. Source hashes, exact mutation locators and generated arithmetic
  replays are provenance/instrumentation controls; they are not independent
  correctness tests. Retain the independent witness that gives them meaning.
- Preserve pre-existing work. Mutation scaffolding uses an isolated copy;
  any harness restoring a file restores its captured prior bytes, never
  `git checkout -- <file>` or a reset to `HEAD`.
- Partial results, non-finite arithmetic, missing evidence, truncated output
  and failed dependencies must be visible. Gate controls distinguish a tool
  that failed to start from a completed test that rejected the intended fault.
- Multi-writer artifacts need unique staging paths, validation and atomic
  publication. Bound retries, buffers and resource use from the supported
  workload; an arbitrary comfortable constant is not a justification.
- Fix the root cause and search same-pattern siblings in the affected numerical
  family, including related implementations when relevant. Record what was
  checked. Fix within the authorized change or a focused stacked PR; defer
  only for a separate design/rollout, reviewability or conflicting in-flight
  work, with remaining sites enumerated in the owning Epic.
- Numerical bug fixes include a deterministic regression that would have
  caught the defect. Update invalidated contracts, derivations, results,
  diagrams and compatibility evidence in the same change. Keep normative
  guidance current-state; retain discovery history in evidence records.

## Performance and Planned Scenario Execution

Measure pricing, admission, IV and Greek costs separately and end to end.
Record hardware, OS, compiler/options, source revision, input corpus, warm-up,
repeated-run variation and host load. Profile allocation/GC and arithmetic
before selecting changes. No calibrated automated performance gate exists;
single-session timing differences do not establish a language-wide advantage.
See [#8](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/8) and
[#16](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/16).

For performance campaigns, follow the [worker/tile tuning guide](docs/planner-worker-tuning.md)
and [operational protocol](docs/operational-campaign.md):

- State the measured path: Fast approximate prices or runtime-certified
  outputs, scalar or batch, compilation or reused execution, requested
  quantities and sink work. Batch time divided by output count is amortized
  cost, not single-request latency. Keep cold-start definitions explicit.
- Finish task-owned builds, tests and profilers before collecting timings.
  Use repeated processes and alternate comparison order; retain all samples
  and host load. A quieter shared machine is not an isolated benchmark host.
- Measure workers and tile size together against a one-worker reference.
  Domain startup can outweigh small Fast workloads. Include first-output
  latency, cancellation and buffer costs before recommending larger tiles or
  more workers; throughput alone does not establish a better configuration.
- Label memory scope: coordinator allocation excludes worker bodies;
  per-process peak RSS is neither allocation volume nor simultaneous
  deployment-wide memory. Collect per-child resource usage from its own reap,
  not cumulative child statistics. Small-sample percentiles are descriptive,
  not tail-latency guarantees.
- Check complete ordered outcomes across worker counts outside timing.
  Preserve failures, cancelled status and uncommitted work; cancelled responses
  do not count as completed-request throughput. Measure cancellation response
  from actual issuance and report scheduling delay separately. Replay equality
  establishes compatibility, not independent numerical accuracy.
- Preserve exact configuration, source/toolchain and binary hashes with raw
  output and partial evidence on failure. Source guards include staged,
  unstaged and untracked changes; a binary hash alone does not prove how it
  was built. Historical reports must keep their measured revisions and hashes.
- Exercise collectors with malformed/truncated output, timeouts, failed
  startup, changed replay and impossible criteria. A negative control must
  reject for the intended reason; a timeout is not evidence that malformed
  output was detected. Keep lightweight controls in CI and timing campaigns
  manual unless a calibrated performance gate is deliberately introduced.

The planner implements immutable scenario plans and bounded execution.
Read [the scenario contract](docs/scenario-planner.md). Its architecture lives in
[Epic #23](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/23). The implementation must preserve these obligations:

- Compile frozen portfolio/market/scenario specifications into an inspectable
  plan; distinguish structural validity from per-item numerical admission.
- Enumerate the Cartesian workload lazily in bounded tiles, with checked
  counts and output-size estimates. Do not allocate the entire result cube
  by default. Preserve stable item IDs, failures and completion status.
- Share immutable inputs; keep scratch and caches worker-owned unless a
  justified synchronization contract says otherwise. Reuse work only when
  all dependencies and conventions match; avoid global mutable caches.
- Fix logical reduction order independently of physical scheduling and worker
  count, and derive its numerical error. Aggregate only compatible units,
  coordinates, currencies and factors. Partial totals are not complete totals.
- The recommended time scenario rolls valuation time with fixed expiries and
  explicit day-count/market conventions. Post-expiry settlement and economic
  P&L require their own contract; do not silently clamp time or invent cashflows.
- OxCaml mode checking is an isolated experiment under
  [#22](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/22), requiring
  checked worker boundaries and negative compile tests. Upstream OCaml
  ownership discipline is not compiler-enforced data-race freedom. Neither
  implies numerical correctness, deterministic aggregation or deadlock freedom.

## Coding Style, Safety, and Dependencies

Use idiomatic OCaml, existing module naming and the pinned ocamlformat style.
Document public signatures in `.mli` files. Comments explain mathematical
constraints and preconditions rather than narrating the edit. Prefer explicit
variants/results over sentinel numbers and exceptions for expected failures.
Keep core kernels deterministic: no uncontrolled clock, unseeded randomness,
hidden mutable state or dependence on unordered iteration.

Keep unsafe operations and foreign code minimal and isolated. New unchecked
access, `Obj.magic`, FFI or allocation annotations require a documented safety
argument, correct bytecode/native behavior and focused verification. The
existing multiplication primitive is not permission for arbitrary foreign
arithmetic. Never commit secrets, credentials or confidential market data.

Add dependencies only when existing facilities are insufficient; assess
maintenance, licensing, security, build and runtime cost. Edit `dune-project`
for generated opam metadata; keep lockfile changes deliberate. Do not add
test-only arbitrary-precision dependencies to the runtime library. Keep shell
wrappers thin and numerical/provenance logic in tested OCaml/Python owners.
For new user-facing CLIs, handle help, version and end-of-options explicitly.
Do not commit `_build/`, virtual environments, decompressed fixtures or
benchmark build products.

## Issues, Pull Requests, and Releases

This project uses **GitHub**, `gh`, and `.github/workflows/`. Do not copy
FerroRisk's GitLab origin, CI stages, Cargo gates or release commands here.

- Every non-bug work issue has a **native GitHub Epic parent**. An `epic:`
  title or body checklist alone is insufficient. Set the actual issue type
  and sub-issue relationship, and verify it. Epics are top-level; Bugs may
  remain standalone but must be linked when they block an Epic's outcome.
- [Epic #27](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/27) owns
  production readiness; [Epic #23](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/23)
  owns scenario planning. Keep one parent per work issue and express shared
  dependencies as links. Keep existing acceptance criteria and unresolved
  limitations intact when reorganizing work.
- `main` is the only long-lived branch. Use focused conventional branches and
  commit/PR titles (`docs/project-guidance`, `fix/iv-termination`, `feat: ...`).
  No direct pushes or force pushes to `main`, no bypassing checks. Keep stacked
  PR dependencies explicit and merge in order; one open PR does not prevent
  authorized work on another concern.
- Use squash merges into `main`; do not rewrite a stacked base casually.
  Required GitHub rulesets include PR review-thread resolution, signatures,
  linear history and the five CI checks listed above. Inspect current settings
  with `gh api repos/MorphIQ-Labs/morphiq-risk-ml/rulesets` and the applicable
  ruleset details; a 404 from classic branch protection does not mean rulesets
  are absent. Do not change repository settings as part of routine code work.
- A PR states the concrete problem, resulting behavior, numerical/compatibility
  impact, local validation and performance evidence where applicable. Put
  `Closes #N` only for issues completely resolved by that change; link partial
  work with its remaining criteria. Confirm closure after the final merge.
  A completed child does not by itself complete its Epic.
- Follow [docs/stability.md](docs/stability.md): public outcomes and served
  numerical values are contracts even at `0.y.z`. Intentional numerical changes
  include before/after reference errors, affected cases and oracle provenance
  in `CHANGELOG.md`, plus the reviewed determinism digest when it changes.
- Versions live in `dune-project` and `Morphiq_risk.version`; releases use
  `vX.Y.Z` from `main`. **There is no automated release workflow here today.**
  Do not claim `prepare-release`, `tag-release`, release-plz or a semver gate
  exists. Do not invent a release/tag as a side effect of completing a PR;
  release acceptance and controls are described in
  [the acceptance dossier](docs/acceptance-and-change-control.md) and tracked in
  [#17](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues/17).

### Engineering completion and external acceptance

Keep campaign completion, specified criteria, deployment acceptance and
independent review distinct. Unset targets or missing observations remain
pending, never passing. Fix acceptance targets and representative inputs
before collecting acceptance evidence; do not choose limits to fit results.
A synthetic local campaign and a successful collector exit do not supply a
deployment recommendation or owner approval.

Reuse the existing [independent review package](docs/independent-review-package.md)
and [acceptance dossier](docs/acceptance-and-change-control.md). Record the exact
candidate covered by evidence; later documentation or harness changes do not
automatically requalify changed runtime code. Do not invent a reviewer, transfer
historical approval to a new candidate, or commission/contact someone without
authorization. When only reviewer selection, deployment requirements or owner
decisions remain, state those dependencies and leave their issues open rather
than generating redundant handoff documents or claiming release readiness.

## Definition of Done

The authorized scope is complete, the defect pattern is addressed, relevant
local checks pass, and evidence states exactly what was tested and what was
not. Changed contracts, references, bounds, manifests, results and compatibility
records agree. Hot-path changes have measured evidence without weakened
correctness. Remaining work has a specific justified disposition in its Epic;
fully resolved issues close through the final PR. No universal proof,
production readiness, performance result or concurrency guarantee is claimed
beyond the evidence actually obtained.
