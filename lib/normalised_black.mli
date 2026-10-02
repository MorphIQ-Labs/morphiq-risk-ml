(** Jäckel's normalised Black function for an out-of-the-money option. *)

val scaled : ?k:int -> float -> float -> float -> float -> float -> float
(** [scaled ~k m x xl s sl] is [2^k * m * b(x + xl, s + sl)] for [x <= 0] and
    [s > 0], where [xl] and [sl] are the low parts of double-double
    log-moneyness and total volatility, and
    [b(x, s) = Phi(x/s + s/2) e^(x/2) - Phi(x/s - s/2) e^(-x/2)].
    The prefactor [m] is folded in before the Gaussian factor, so the
    result underflows only once. *)

val y_prime : float -> float
(** [1 + h Y(h)] with [Y = Phi / phi], for [h <= 0]. *)

val inv_sqrt_2pi : float
