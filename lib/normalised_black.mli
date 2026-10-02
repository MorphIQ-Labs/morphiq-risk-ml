(** Jäckel's normalised Black function for an out-of-the-money option. *)

val scaled : ?k:int -> float -> float -> float -> float -> float -> float
(** [scaled ~k m x xl s sl] is [2^k * m * b(x + xl, s + sl)] for [x <= 0] and
    [s > 0], where [xl] and [sl] are the low parts of double-double
    log-moneyness and total volatility, and
    [b(x, s) = Phi(x/s + s/2) e^(x/2) - Phi(x/s - s/2) e^(-x/2)]. The prefactor
    [m] is folded in before the Gaussian factor, so the result underflows only
    once. *)

val y_prime : float -> float
(** [1 + h Y(h)] with [Y = Phi / phi], for [h <= 0]. *)

val inv_sqrt_2pi : float

val b : float -> float -> float
(** [b x s] for [x <= 0], [s > 0]. *)

val vega : float -> float -> float
(** [db/ds = exp(-((x/s)^2 + (s/2)^2)/2) / sqrt(2 pi)]. *)

val inv_vega : float -> float -> float
val ln_vega : float -> float -> float

val scaled_and_ln_vega : float -> float -> float * float
(** [(b / vega, ln vega)], for [x < 0], [s > 0]. *)

val sqrt_two_pi : float

val complement : float -> float -> float -> float -> float
(** [complement x xl s sl] is [e^(x/2) - b(x + xl, s + sl)] for [x <= 0],
    without subtractive cancellation. *)

val vega_exponent : float -> float -> float -> float -> float * float
(** [vega_exponent hh hl t tl] is [(h^2 + t^2)/2] as an unevaluated sum, for
    [h = hh + hl] and [t = t + tl]. *)

val ln_b_and_scaled : float -> float -> float -> float * float
(** [(ln b, b / vega)] at log-moneyness [x + xl] and total volatility [s], for
    [x < 0]. Neither underflows where [b] does. *)
