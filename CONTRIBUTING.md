# Contributing

Bug reports, reproducible numerical counterexamples, documentation improvements,
and focused pull requests are welcome. Start with an
[issue](https://github.com/MorphIQ-Labs/morphiq-risk-ml/issues) before proposing a
new model, changing a public contract, or adding a dependency.

This is an OCaml/Dune/opam project. This guide takes precedence over the
organization's generic Rust contribution and release instructions.
[AGENTS.md](AGENTS.md) records the detailed engineering contract;
[docs/README.md](docs/README.md) identifies its supporting documentation.

## Development environment

Use OCaml 5.3.0 with Flambda, Python 3, and ocamlformat 0.27.0. Create the switch
only if it does not already exist:

```sh
opam switch create morphiq-risk-ml --packages=ocaml-variants.5.3.0+options,ocaml-option-flambda
opam install --switch=morphiq-risk-ml . --deps-only --with-test --locked
opam install --switch=morphiq-risk-ml ocamlformat.0.27.0
opam exec --switch=morphiq-risk-ml -- ocamlopt -config-var flambda
```

The last command must print `true`. The locked dependencies are intentional;
edit `dune-project` for package metadata and change dependency pins deliberately.

## Checks

```sh
opam exec --switch=morphiq-risk-ml -- dune build @install
opam exec --switch=morphiq-risk-ml -- dune build @fmt
opam exec --switch=morphiq-risk-ml -- dune runtest
```

CI builds and tests on three platforms, checks formatting, and runs the seven
core mutation mechanisms. Run affected mutation witnesses for numerical changes:

```sh
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- --core
opam exec --switch=morphiq-risk-ml -- dune exec scripts/mutation/mutation.exe -- --list
```

The full mutation catalog and larger performance/reference campaigns are manual
or scheduled work. Do not add them to default PR CI incidentally. See
[mutation policy](docs/mutation-policy.md) and [oracle regeneration](docs/oracles.md).
Documentation-only changes need link checks, build, formatting, and diff checks;
they do not require a new numerical campaign.

## Numerical contributions

Describe the exact quantity, domain, units, and failure outcomes before changing
an algorithm. Supply an independently justified regression from original inputs,
including exact floating-point words where rounding matters. Report reference
uncertainty and unresolved cases. Do not tune tolerances, omit difficult cases,
or treat agreement between two binary64 implementations as a proof.

Preserve explicit multiplication/FMA semantics, typed admission and units, and
the distinction between fast estimates and runtime-certified results. Changes
to served values or outcomes require the evidence and compatibility assessment
in [the stability policy](docs/stability.md). Performance changes need controlled
before/after measurements with an unchanged numerical contract.

For bug reports, include the commit/version, compiler and platform, a minimal
reproduction, expected and actual outcomes, and the source of the expectation.
Do not include account credentials, private portfolios, or restricted datasets.

## Pull requests

Use a focused branch and a conventional title such as `fix: ...`, `feat: ...`,
or `docs: ...`. Explain the problem, resulting behavior, validation, and any
numerical or API compatibility impact. Link the issue; use `Closes #N` only
when the full issue is resolved.

`main` requires a PR, all five app-bound CI checks on an up-to-date branch,
verified commit signatures, and resolved review threads. It blocks force pushes
and deletion, and merges are squash-only. There is no configured bypass.
The current solo-maintainer policy does not require a second person's approval;
existing approvals are dismissed after new reviewable commits.

Do not commit `_build/`, local environments, decompressed fixtures, scratch
benchmarks, or downloaded research papers. Follow the
[research preservation policy](docs/research/README.md#preservation-and-access)
for acquired papers. Retain the fixtures, hashes, and
evidence that support numerical claims. Upstream code needs provenance and its
original notices; see [third-party notices](THIRD_PARTY_NOTICES.md).

By intentionally submitting original work for inclusion, you contribute it
under Apache-2.0, unless explicitly stated otherwise, as described in section 5
of [LICENSE](LICENSE). You must have the right to submit it. Identify third-party
material and its terms separately; do not replace its notices with ours.

Merging a PR does not publish a release. Candidate validation and release
acceptance follow [the change-control contract](docs/acceptance-and-change-control.md).

For suspected exploitable vulnerabilities, follow [SECURITY.md](SECURITY.md)
and use private reporting before sharing details in public issues.
