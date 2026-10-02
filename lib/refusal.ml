type parameter =
  | Spot
  | Forward
  | Strike
  | Time_to_expiry
  | Rate
  | Dividend_yield
  | Displacement
  | Shifted_forward
  | Shifted_strike
  | Volatility
  | Price

type t = Invalid_input of { parameter : parameter; value : float }

let parameter_name = function
  | Spot -> "spot"
  | Forward -> "forward"
  | Strike -> "strike"
  | Time_to_expiry -> "time_to_expiry"
  | Rate -> "rate"
  | Dividend_yield -> "dividend_yield"
  | Displacement -> "displacement"
  | Shifted_forward -> "shifted_forward"
  | Shifted_strike -> "shifted_strike"
  | Volatility -> "volatility"
  | Price -> "price"

let to_string (Invalid_input { parameter; value }) =
  Printf.sprintf "invalid input %s = %h" (parameter_name parameter) value
