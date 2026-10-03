(* Positive-maturity, zero-volatility ATM time derivative of right vega.
   See docs/zero-volatility-greeks.md. Every returned value is certified to
   nearest-even binary64; arithmetic uncertainty is not a payoff kink. *)
module E = Enclosure

let even x = Int64.logand (Int64.bits_of_float x) 1L = 0L

let midpoint lower upper =
  E.add (E.exact lower) (E.scale (E.sub (E.exact upper) (E.exact lower)) (-1))

let rounded value =
  let accepts candidate =
    if not (Float.is_finite candidate) then false
    else if E.compare_float value candidate = E.Zero then true
    else
      let lower = Float.pred candidate and upper = Float.succ candidate in
      if not (Float.is_finite lower && Float.is_finite upper) then false
      else
        let left = E.sign (E.sub value (midpoint lower candidate))
        and right = E.sign (E.sub value (midpoint candidate upper)) in
        (left = E.Positive || (left = E.Zero && even candidate))
        && (right = E.Negative || (right = E.Zero && even candidate))
  in
  match
    List.find_opt accepts [ value.hi; Float.pred value.hi; Float.succ value.hi ]
  with
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
