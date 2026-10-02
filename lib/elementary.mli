(** Deterministic elementary functions: IEEE-754 basic operations and fma only,
    so they give the same bits on every conforming platform, unlike the system
    libm. About 1 ULP (test/oracle_elementary.ml). *)

val exp : float -> float
val expm1 : float -> float
val log : float -> float
val log1p : float -> float

val cbrt : float -> float
(** For initial guesses: deterministic, about 1 ULP. *)
