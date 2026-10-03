(** Bounded inversion of an increasing binary64 evaluator. This is an arithmetic
    termination contract, not a bound on the evaluator's error against a real
    function. *)

type failure = Non_convergence | Numerical_failure

val refine :
  value:(float -> float) ->
  target:float ->
  candidate:float ->
  (float, failure) result
(** Validate a candidate with its adjacent floats, falling back to a bounded
    solve on [candidate/2, candidate*2] when that interval brackets the target.
    Failure to construct the bracket is explicit. *)

val solve :
  ?max_iterations:int ->
  value:(float -> float) ->
  proposal:(float -> float -> float) ->
  target:float ->
  lower:float ->
  upper:float ->
  initial:float ->
  unit ->
  (float, failure) result
(** Returns only an evaluated exact match or the closer endpoint of an
    adjacent-float bracket. Endpoint values must bracket [target]. Every fourth
    step bisects the ordered positive binary64 encodings, so at most 252 steps
    exhaust the representable interval. A smaller caller-supplied limit returns
    [Non_convergence]; it never turns an iterate into success. A failed proposal
    falls back to bisection. A nonfinite value, invalid bracket is
    [Numerical_failure]. Rounded evaluator values need not be monotone between
    adjacent floats; the endpoint sign invariant is enough for the stated
    discrete bracket guarantee. *)
