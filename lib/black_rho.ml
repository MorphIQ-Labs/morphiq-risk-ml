(* Original-input BSM rho with exponent restoration after the rounding proof.
   See docs/rho-subnormal-design.md. *)
module E = Enclosure

let rounded ~exponent value =
  let magnitude = E.magnitude value in
  if
    Float.is_finite magnitude && magnitude > 0.0
    && snd (Float.frexp magnitude) + exponent <= -1075
  then Some (Float.copy_sign 0.0 value.hi)
  else Enclosure_round.nearest ~exponent value

let evaluate ~spot ~spot_low ~strike ~strike_low ~time ~rate ~yield side sigma =
  try
    let spot = E.of_words spot spot_low
    and strike_value = E.of_words strike strike_low in
    let tm, te = Float.frexp time and _, ke = Float.frexp strike in
    let t = E.exact time in
    let coefficient () =
      let normalized = E.mul (E.exact tm) (E.scale strike_value (-ke)) in
      let quarter = E.exp (E.scale (E.neg (E.mul (E.exact rate) t)) (-2)) in
      let half = E.mul quarter quarter in
      E.mul normalized (E.mul half half)
    in
    let log_ratio =
      if spot = strike_value then E.exact 0.0
      else E.sub (E.log spot) (E.log strike_value)
    in
    let x = E.add log_ratio (E.mul (E.sub (E.exact rate) (E.exact yield)) t) in
    let theta = Side.sign side in
    let value, exponent =
      if sigma = 0.0 then
        match E.sign (E.mul_float x theta) with
        | E.Positive -> (E.mul_float (coefficient ()) theta, te + ke)
        | E.Negative -> (E.exact 0.0, 0)
        | E.Zero | E.Indeterminate -> raise (E.Unresolved "rho boundary sign")
      else
        let total = E.mul (E.exact sigma) (E.sqrt t) in
        let d2 = E.sub (E.div x total) (E.scale total (-1)) in
        let argument = E.mul_float d2 theta in
        let below_zero_cell =
          try
            match E.compare_float argument (-1.0) with
            | E.Negative | E.Zero ->
                (* Phi(-z) < exp(-z²/2) for z >= 1, by the Mills integral
                 bound. Compare the full rho magnitude in log space before
                 the CDF's conservative binary64 tail floor is introduced. *)
                let log_upper =
                  E.sub
                    (E.sub
                       (E.add (E.log t) (E.log strike_value))
                       (E.mul (E.exact rate) t))
                    (E.scale (E.mul argument argument) (-1))
                in
                let midpoint_log =
                  E.mul_float (E.log (E.exact 2.0)) (-1075.0)
                in
                E.sign (E.sub log_upper midpoint_log) = E.Negative
            | E.Positive | E.Indeterminate -> false
          with E.Unresolved _ -> false
        in
        let direct () =
          ( E.mul_float
              (E.mul (coefficient ()) (Model_enclosure.cdf argument))
              theta,
            te + ke )
        in
        if below_zero_cell then (E.exact 0.0, 0)
        else
          match E.compare_float argument (-4.0) with
          | E.Negative | E.Zero -> (
              try
                (* Form the whole tail rho in minimum-subnormal units. A CDF
                 rounded into subnormals first cannot certify the product. *)
                let log_scaled_density =
                  E.add
                    (E.sub
                       (E.sub
                          (E.add (E.log t) (E.log strike_value))
                          (E.mul (E.exact rate) t))
                       (E.scale (E.mul argument argument) (-1)))
                    (E.mul_float (E.log (E.exact 2.0)) 1074.0)
                in
                let density =
                  E.div (E.exp log_scaled_density)
                    (E.sqrt (E.mul_float Model_enclosure.pi 2.0))
                in
                ( E.mul_float
                    (E.mul density (Model_enclosure.mills (E.neg argument)))
                    theta,
                  -1074 )
              with E.Unresolved _ -> direct ())
          | E.Positive | E.Indeterminate -> direct ()
    in
    match rounded ~exponent value with
    | Some value ->
        Ok
          (if value = 0.0 && sigma > 0.0 then Float.copy_sign 0.0 theta
           else value)
    | None -> Error Greeks.Numerical_failure
  with E.Unresolved _ -> Error Greeks.Numerical_failure
