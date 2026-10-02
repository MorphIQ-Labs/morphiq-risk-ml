type lognormal
type normal
type _ t = float

let admit v =
  if Float.is_finite v && v >= 0.0 then Ok v
  else Error (Refusal.Invalid_input { parameter = Refusal.Volatility; value = v })

let lognormal = admit
let normal = admit
let to_float v = v
