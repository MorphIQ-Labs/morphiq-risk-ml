type t
(** Private coarse native boundary for admitted middle-OTM Bachelier values.
    Stored inputs and outputs do not alias caller arrays. The scalar flag is an
    assurance control; ordinary dispatch uses SIMD only on ARM64. *)

val backend : int
val default_enabled : bool
val compile : Bachelier.Fast_middle.t array -> t
val length : t -> int
val execute : ?scalar:bool -> t -> float array
