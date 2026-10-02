(** The outcome of inverting a quote for its volatility.

    Every quote either has an inverse or belongs to exactly one class that
    explains why it has none. The classes follow FerroRisk #448's
    identifiability table, and callers must handle each of them. *)

type 'coordinate t =
  | Root of 'coordinate Vol.t
      (** The volatility whose exact model price is the quote, which is taken
          as an exact number. Zero when the quote is the discounted intrinsic,
          or its correctly rounded value below it (#448). A quote that rounds
          the intrinsic upward has a positive exact root, and that root
          reprices to the quote. *)
  | Below_intrinsic  (** Below the zero-volatility price: no volatility attains it. *)
  | Above_maximum
      (** At or above the price as volatility goes to infinity, or with a root
          above the largest finite volatility. *)
  | Not_identifiable_at_expiry  (** At expiry the price does not depend on volatility. *)
  | Below_smallest_volatility  (** The root is below the smallest positive binary64. *)
