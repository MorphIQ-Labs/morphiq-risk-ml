(** Standard normal distribution.

    Every function returns NaN for a NaN argument. *)

val norm_pdf : float -> float
(** Density [phi(x)]. Symmetric bit for bit: [norm_pdf x = norm_pdf (-.x)]. *)

val norm_cdf : float -> float
(** Distribution [Phi(x)], built on project-generated error functions. The
    tail's [exp(-x^2/2)] uses an exactly split square, so the rounding of the
    argument does not grow with [x^2]. *)

val log_norm_cdf : float -> float
(** [ln Phi(x)]. Returns [-0.0] or [neg_infinity] where the value is not
    representable. *)

val norm_inv : float -> float
(** [Phi^-1(p)] by bounded, safeguarded Gaussian-integral inversion. Returns
    [neg_infinity] at 0, [infinity] at 1, and NaN outside [[0, 1]]. *)

val norm_cdf_dd : float -> float -> float
(** [norm_cdf_dd hi lo] is [Phi(hi + lo)] for [|lo| <= ulp(hi)], to first order
    in [lo]. *)

val inv_sqrt_2 : float
