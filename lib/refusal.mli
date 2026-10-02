(** Why an input is not admitted.

    The slice has no model/exercise-style refusal. Exercise style is not an
    input, so an American request to a European model cannot be built. *)

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

type t = Invalid_input of { parameter : parameter; value : float }

val to_string : t -> string
