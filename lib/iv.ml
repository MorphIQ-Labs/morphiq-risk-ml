type 'coordinate t =
  | Root of 'coordinate Vol.t
  | Below_intrinsic
  | Above_maximum
  | Not_identifiable_at_expiry
  | Below_smallest_volatility
  | Non_convergence
  | Numerical_failure
