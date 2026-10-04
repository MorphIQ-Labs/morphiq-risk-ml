(** Test-only ULP distance. Signed zeros share rank zero. Nonfinite values are
    never numerical accuracy successes; expected endpoint/domain classes must be
    checked separately by the caller. *)
val distance : float -> float -> Z.t option
(** Exact nonnegative count of representable steps, including across zero. *)

val ulps : float -> float -> float
(** Distance rounded upward to binary64, or infinity for nonfinite operands.
    Upward conversion cannot make a finite ULP budget accept an excessive count.
*)

val within : budget:float -> float -> float -> bool
(** Exact integer comparison against a finite, nonnegative binary64 budget. *)
