(** Units carried by Greeks, as types.

    A time derivative is quoted per calendar day (FerroRisk convention:
    [-d/dT / 365]) and cannot be passed where an annual rate is expected without
    {!annualise}. A volatility derivative is tagged with its volatility
    coordinate, so a Black vega and a Bachelier vega do not mix. *)

type per_year
type per_calendar_day
type 'unit time_rate = private float
type 'coordinate per_volatility = private float
type 'coordinate per_volatility_squared = private float

type ('unit, 'coordinate) volatility_time_rate = private float
(** A time derivative of a volatility sensitivity, retaining both tags. *)

val per_calendar_day : float -> per_calendar_day time_rate
(** From an annual rate [-dV/dT]. *)

val annualise : per_calendar_day time_rate -> per_year time_rate

val time_rate : float -> 'unit time_rate
(** Attach a caller-established time unit to a raw value. No conversion,
    finite-value check or validation of the caller-selected tag is performed.
    This is a trusted labeling boundary, not proof of a value's provenance. *)

val per_volatility : float -> 'coordinate per_volatility
(** Attach the caller-established volatility coordinate without conversion or
    validation. Keep typed model outputs typed instead of extracting and
    relabeling their floats. *)

val per_volatility_squared : float -> 'coordinate per_volatility_squared
(** Trusted labeling of a second volatility derivative; no validation. *)

val volatility_time_rate : float -> ('unit, 'coordinate) volatility_time_rate
(** Trusted labeling of a mixed time/volatility derivative; no conversion or
    validation of either tag. *)

val annualise_volatility :
  (per_calendar_day, 'coordinate) volatility_time_rate ->
  (per_year, 'coordinate) volatility_time_rate
(** Multiply by 365, preserving the volatility coordinate. Like {!annualise},
    this conversion follows binary64 arithmetic and can overflow. *)

val days_per_year : float
