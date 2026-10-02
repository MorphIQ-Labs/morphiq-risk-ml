(** The standard normal density and distribution in double-double. *)

val limit : float
(** {!cdf} accepts [|d| <= limit] (6). *)

val pdf : Dd.t -> Dd.t
val cdf : Dd.t -> Dd.t
