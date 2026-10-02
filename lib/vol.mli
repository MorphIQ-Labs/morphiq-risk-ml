(** Volatility, tagged with its coordinate.

    A lognormal (Black) volatility is dimensionless per root year. A normal
    (Bachelier) volatility is in price units per root year. The two are distinct
    types, so one cannot be passed where the other is expected. *)

type lognormal
type normal

type 'coordinate t = private float
(** A finite, nonnegative volatility in ['coordinate]. *)

val lognormal : float -> (lognormal t, Refusal.t) result
val normal : float -> (normal t, Refusal.t) result
val to_float : _ t -> float
