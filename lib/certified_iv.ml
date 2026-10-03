(* Every successful decision concerns the real model, not a rounded evaluator.
   See docs/certified-iv.md for the rounding-cell and finite-work argument. *)

type outcome =
  | Root of float
  | Below_intrinsic
  | Above_maximum
  | Below_smallest_volatility
  | Non_convergence
  | Numerical_failure

module Make (E : Enclosure.S) = struct
  let midpoint lower upper =
    E.add (E.exact lower) (E.scale (E.sub (E.exact upper) (E.exact lower)) (-1))

  let even x = Int64.logand (Int64.bits_of_float x) 1L = 0L
  let maximum_bits = Int64.bits_of_float Float.max_float

  let solve ?(max_steps = 128) ~prepare_residual ~intrinsic ~maximum ~quote
      ~proposal () =
    let exception Stop of outcome in
    let stop outcome = raise (Stop outcome) in
    let unresolved () = stop Numerical_failure in
    let steps = ref 0 in
    let step () =
      if !steps >= max_steps then stop Non_convergence;
      incr steps
    in
    (* Owned by this synchronous call; classification runs before potentially
     unrepresentable residual normalization. It never escapes to a worker. *)
    let residual = lazy (prepare_residual ()) in
    let sign argument = E.sign ((Lazy.force residual) argument) in
    let sign_float argument =
      if argument = 0.0 then E.compare_float intrinsic quote
      else sign (E.exact argument)
    in
    let rounding_cell candidate =
      if candidate <= 0x1p-1074 || candidate = Float.max_float then false
      else
        let lower = sign (midpoint (Float.pred candidate) candidate)
        and upper = sign (midpoint candidate (Float.succ candidate)) in
        (lower = E.Negative || (lower = E.Zero && even candidate))
        && (upper = E.Positive || (upper = E.Zero && even candidate))
    in
    let rec bisect lower upper =
      if Float.succ lower >= upper then
        if lower = 0.0 then stop Below_smallest_volatility
        else
          match sign (midpoint lower upper) with
          | E.Negative -> Root upper
          | E.Positive -> Root lower
          | E.Zero -> Root (if even lower then lower else upper)
          | E.Indeterminate -> Numerical_failure
      else (
        step ();
        let l = Int64.bits_of_float lower and h = Int64.bits_of_float upper in
        let candidate =
          Int64.float_of_bits (Int64.add l (Int64.div (Int64.sub h l) 2L))
        in
        match sign_float candidate with
        | E.Negative -> bisect candidate upper
        | E.Positive -> bisect lower candidate
        | E.Zero -> Root candidate
        | E.Indeterminate ->
            if rounding_cell candidate then Root candidate
            else Numerical_failure)
    in
    let bracket candidate direction =
      let origin = Int64.bits_of_float candidate in
      let endpoint = if direction = E.Negative then maximum_bits else 0L in
      let available = Int64.abs (Int64.sub endpoint origin) in
      let rec expand offset =
        step ();
        let distance = Int64.min offset available in
        let bits =
          if direction = E.Negative then Int64.add origin distance
          else Int64.sub origin distance
        in
        let next = Int64.float_of_bits bits in
        match sign_float next with
        | E.Zero -> Root next
        | E.Indeterminate ->
            if rounding_cell next then Root next else Numerical_failure
        | result when result <> direction ->
            if direction = E.Negative then bisect candidate next
            else bisect next candidate
        | _ when bits = maximum_bits -> Above_maximum
        | _ when bits = 0L -> Numerical_failure
        | _ ->
            let offset =
              if offset >= Int64.div maximum_bits 2L then maximum_bits
              else Int64.mul offset 2L
            in
            expand offset
      in
      expand 1L
    in
    try
      if max_steps < 0 || not (Float.is_finite quote && quote >= 0.0) then
        unresolved ();
      (match maximum with
      | None -> ()
      | Some maximum -> (
          match E.compare_float maximum quote with
          | E.Positive -> ()
          | E.Zero | E.Negative -> stop Above_maximum
          | E.Indeterminate -> unresolved ()));
      (match E.compare_float intrinsic quote with
      | E.Zero -> stop (Root 0.0)
      | E.Indeterminate -> unresolved ()
      | E.Positive -> (
          if quote = Float.max_float then unresolved ();
          match
            E.sign (E.sub intrinsic (midpoint quote (Float.succ quote)))
          with
          | E.Negative -> stop (Root 0.0)
          | E.Zero -> stop (if even quote then Root 0.0 else Below_intrinsic)
          | E.Positive -> stop Below_intrinsic
          | E.Indeterminate -> unresolved ())
      | E.Negative -> ());
      if not (Float.is_finite proposal && proposal > 0.0) then unresolved ();
      if max_steps = 0 then stop Non_convergence;
      if rounding_cell proposal then Root proposal
      else
        match sign_float proposal with
        | E.Zero -> Root proposal
        | E.Indeterminate -> Numerical_failure
        | E.Positive when proposal = 0x1p-1074 -> Below_smallest_volatility
        | direction -> bracket proposal direction
    with
    | E.Unresolved _ -> Numerical_failure
    | Stop outcome -> outcome
end

include Make (Enclosure)
module Fast = Make (Enclosure.Fast)
