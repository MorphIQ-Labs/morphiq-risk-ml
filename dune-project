(lang dune 3.16)

(name morphiq_risk_ml)

(version 0.3.0)

(generate_opam_files true)

(source
 (github MorphIQ-Labs/morphiq-risk-ml))

(authors "MorphIQ Labs contributors")

(maintainers "Stephen Romano <thestephenromano@gmail.com>")

(license Apache-2.0)

(package
 (name morphiq_risk_ml)
 (synopsis "European option pricing and deterministic portfolio scenarios in OCaml")
 (description
  "European pricing, certified implied volatility, typed analytic Greeks, and bounded deterministic scenario execution for BSM, Black-76, displaced Black, and Bachelier. Runtime numerical acceptance requires explicit caller-selected absolute error limits. Third-party provenance status is recorded in THIRD_PARTY_NOTICES.md.")
 (depends
  (ocaml (>= 5.3))
  ocaml-option-flambda
  (zarith :with-test)
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
