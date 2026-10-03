(** The outcome of inverting a quote for its volatility.

    Mathematical classifications and computational failures are distinct.
    Failure does not imply that a mathematical inverse is absent. *)

type 'coordinate t =
  | Root of 'coordinate Vol.t
      (** A positive value is the nearest-even binary64 rounding of the real
          inverse of the exact quote, established by runtime model enclosures
          under the documented IEEE arithmetic contract. Exact repricing is not
          promised. Unresolved enclosures return [Numerical_failure]. See
          docs/certified-iv.md. Zero when the quote is the discounted intrinsic,
          or its correctly rounded value below it (#448). A quote that rounds
          the intrinsic upward has a positive real root. *)
  | Below_intrinsic
      (** Below the zero-volatility price: no volatility attains it. *)
  | Above_maximum
      (** At or above the price as volatility goes to infinity, or with a root
          above the largest finite volatility. *)
  | Not_identifiable_at_expiry
      (** At expiry the price does not depend on volatility. *)
  | Below_smallest_volatility
      (** The root is below the smallest positive binary64. *)
  | Non_convergence
      (** The finite iteration budget was exhausted without satisfying the
          solver's stopping criterion. No successful iterate is returned. *)
  | Numerical_failure
      (** Arithmetic, a boundary comparison or the root's rounding cell could
          not be resolved. This is not evidence of a price above the
          mathematical maximum or of a root below the smallest volatility. *)
