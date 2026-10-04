(** The standard normal density and distribution in double-double. *)

val limit : float
(** {!cdf} accepts [|d| <= limit] (6). *)

val pdf : Dd.t -> Dd.t
val cdf : Dd.t -> Dd.t

val cdf_and_pdf : Dd.t -> Dd.t * Dd.t
(** [(cdf d, pdf d)] sharing the same rounded square and density. The domain and
    error bounds are those of {!cdf} and {!pdf}. *)
