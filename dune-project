(lang dune 3.16)

(name morphiq_risk_ml)

(generate_opam_files true)

(package
 (name morphiq_risk_ml)
 (synopsis "OCaml slice experiment rebuilding the FerroRisk European engine")
 (depends
  (ocaml (>= 5.3))
  ocaml-option-flambda
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
