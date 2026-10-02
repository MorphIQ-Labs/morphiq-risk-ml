(* A volatility is only made by its admission, which refuses negatives. *)
open Morphiq_risk

let (_ : Vol.lognormal Vol.t) = -0.2
