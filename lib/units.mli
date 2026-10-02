(** Units carried by Greeks, as types.

    A time derivative is quoted per calendar day (FerroRisk convention:
    [-d/dT / 365]) and cannot be passed where an annual rate is expected
    without {!annualise}. A volatility derivative is tagged with its
    volatility coordinate, so a Black vega and a Bachelier vega do not mix. *)

type per_year
type per_calendar_day
type 'unit time_rate = private float
type 'coordinate per_volatility = private float
type 'coordinate per_volatility_squared = private float

val per_calendar_day : float -> per_calendar_day time_rate
(** From an annual rate [-dV/dT]. *)

val annualise : per_calendar_day time_rate -> per_year time_rate
val time_rate : float -> 'unit time_rate
val per_volatility : float -> 'coordinate per_volatility
val per_volatility_squared : float -> 'coordinate per_volatility_squared

val days_per_year : float
