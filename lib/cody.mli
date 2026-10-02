(** Cody's error-function approximations (netlib specfun [CALERF]). *)

val thresh : float
(** Boundary of the first interval, [0.46875]. *)

val erf_small : float -> float
(** [erf x] for [|x| <= thresh]. *)

val erfcx_nonnegative : float -> float
(** [exp(y^2) erfc(y)] for [y >= 0]. *)

val erfcx : float -> float
(** [exp(x^2) erfc(x)]. [infinity] below CALERF's [XNEG = -26.628]. *)

val erf : float -> float
