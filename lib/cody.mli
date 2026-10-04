(** Project-derived error functions; the historical module name is retained for
    compatibility on the unstable Internal surface. Coefficients are generated
    from rational Gaussian-integral enclosures, not CALERF tables. *)

val thresh : float
(** Boundary of the odd small-erf polynomial, [0.5]. *)

val erf_small : float -> float
(** [erf x] for [|x| <= thresh], preserving relative accuracy near zero. *)

val erfcx_nonnegative : float -> float
(** [exp(x²) erfc(x)] for [x >= 0], including infinity and subnormal results. *)

val erfcx : float -> float
(** [exp(x²) erfc(x)], with negative overflow and explicit NaN/infinity
    handling. *)

val erf : float -> float
val erfc : float -> float
