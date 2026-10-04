val nearest : ?exponent:int -> Enclosure.t -> float option
(** A finite nearest-even value of [2^exponent * value] only when the whole
    enclosure proves its cell. Cell endpoints are compared at the unscaled
    exponent, preserving half-subnormal boundaries when that scaling is exact.
    An unresolved cell or nonfinite result returns [None]. Arithmetic outside
    the enclosure domain may raise [Enclosure.Unresolved]. *)
