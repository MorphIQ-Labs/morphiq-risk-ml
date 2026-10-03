(** Exact-model inverse acceptance; see docs/certified-iv.md. *)
type outcome =
  | Root of float
  | Below_intrinsic
  | Above_maximum
  | Below_smallest_volatility
  | Non_convergence
  | Numerical_failure

val solve :
  ?max_steps:int ->
  prepare_residual:(unit -> Enclosure.t -> Enclosure.t) ->
  intrinsic:Enclosure.t ->
  maximum:Enclosure.t option ->
  quote:float ->
  proposal:float ->
  unit ->
  outcome
(** [prepare_residual ()] must return an enclosure of a positive scaling of
    [price-quote], for a continuous strictly increasing real price on positive
    volatility with the supplied intrinsic and optional supremum. A positive
    Root is the nearest-even binary64 inverse; zero uses the documented
    intrinsic-rounding convention. The proposal is untrusted. Arithmetic/sign
    uncertainty and exhausted work are explicit failures. Residual preparation
    happens only after boundary classification. *)
