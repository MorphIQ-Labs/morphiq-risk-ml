(* Both attempts have the same exact-model acceptance criterion. The cheaper
   arithmetic is allowed to be inconclusive, never to supply an unchecked root. *)
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

module Engine
    (E : Enclosure.S)
    (M : Model_enclosure.S with type scalar = E.t)
    (Solver : sig
      val solve :
        ?max_steps:int ->
        prepare_residual:(unit -> E.t -> E.t) ->
        intrinsic:E.t ->
        maximum:E.t option ->
        quote:float ->
        proposal:float ->
        unit ->
        Certified_iv.outcome
    end) =
struct
  let run inputs side ~quote ~proposal =
    try
      let model =
        match inputs with
        | Black c ->
            M.black ~spot:c.spot ~spot_low:c.spot_low ~strike:c.strike
              ~strike_low:c.strike_low ~time:c.time ~rate:c.rate ~yield:c.yield
        | Normal c ->
            M.normal ~forward:c.forward ~strike:c.strike ~time:c.time
              ~rate:c.rate
      in
      let intrinsic, maximum = M.bounds model side in
      Solver.solve
        ~prepare_residual:(fun () -> M.inverse_residual model side quote)
        ~intrinsic ~maximum ~quote ~proposal ()
    with E.Unresolved _ -> Certified_iv.Numerical_failure
end

module First =
  Engine (Enclosure.Fast) (Model_enclosure.Fast) (Certified_iv.Fast)

module Full = Engine (Enclosure) (Model_enclosure) (Certified_iv)

let first_attempt = First.run

let solve inputs side ~quote ~proposal =
  match first_attempt inputs side ~quote ~proposal with
  | Certified_iv.Numerical_failure | Certified_iv.Non_convergence ->
      Full.run inputs side ~quote ~proposal
  | proved -> proved
