(** The outcome of inverting a quote for its volatility.

    Mathematical classifications and computational failures are distinct.
    Failure does not imply that a mathematical inverse is absent. *)

type 'coordinate t =
  | Root of 'coordinate Vol.t
      (** A representable approximation to the inverse of the exact binary64
          quote. An arbitrary real root need not be representable, and exact
          repricing is not promised. See docs/error-analysis.md section 6 for
          the accuracy evidence and its scope. Zero when the quote is the
          discounted intrinsic, or its correctly rounded value below it (#448).
          A quote that rounds the intrinsic upward has a positive real root. *)
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
      (** Arithmetic, a bracket or a conversion could not be resolved. This is
          not evidence of a price above the mathematical maximum or of a root
          below the smallest volatility. *)
