(* Positive-maturity, zero-volatility ATM time derivative of right vega.
   See docs/zero-volatility-greeks.md. Every returned value is certified to
   nearest-even binary64; arithmetic uncertainty is not a payoff kink. *)
module E = Enclosure

let rounded value =
  match Enclosure_round.nearest value with
  | Some value -> Ok value
  | None -> Error Greeks.Numerical_failure

let veta ~weight ~weight_low ~rate ~time =
  try
    let rt = E.mul (E.exact rate) (E.exact time) in
    let factor = E.sub rt (E.exact 0.5) in
    if E.sign factor = E.Zero then Ok 0.0
    else
      let quarter = E.exp (E.scale (E.neg rt) (-2)) in
      let square = E.mul quarter quarter in
      let discount = E.mul square square in
      let density = Model_enclosure.pdf (E.exact 0.0) in
      let weight = E.of_words weight weight_low in
      let numerator = E.mul (E.mul weight discount) (E.mul density factor) in
      let annual = E.div numerator (E.sqrt (E.exact time)) in
      rounded (E.div_float annual Units.days_per_year)
  with E.Unresolved _ -> Error Greeks.Numerical_failure
