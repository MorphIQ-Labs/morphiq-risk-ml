(** Finite refinement between two enclosed implementations of the same model. *)
type model =
  | Black of {
      spot : float;
      spot_low : float;
      strike : float;
      strike_low : float;
      time : float;
      rate : float;
      yield : float;
    }
  | Normal of { forward : float; strike : float; time : float; rate : float }

val solve :
  model -> Side.t -> quote:float -> proposal:float -> Certified_iv.outcome
(** An inconclusive first attempt retries the full evaluator. Every returned
    root or classification has the same certificate; no tolerance is relaxed. *)

val first_attempt :
  model -> Side.t -> quote:float -> proposal:float -> Certified_iv.outcome
(** Research/diagnostic surface for the cheaper attempt's availability. This has
    the same success contract and may refuse more inputs than [solve]. *)
