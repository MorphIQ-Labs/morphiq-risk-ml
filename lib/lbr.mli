(** Implied normalised Black volatility (Jäckel, "Let's Be Rational"). *)

val solve : ?beta_bar:float -> ?ln_beta:float -> float -> float -> float
(** [solve ?beta_bar ?ln_beta beta x] is the [s] with [b(x, s) = beta] for
    [x <= 0] and [0 < beta < e^(x/2)]. [beta_bar] is [e^(x/2) - beta] and
    [ln_beta] is [ln beta], for a caller that knows them more accurately than
    they can be recovered from [beta]. *)
