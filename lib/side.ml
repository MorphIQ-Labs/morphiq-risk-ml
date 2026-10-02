type t = Call | Put

(* +1 for a call, -1 for a put. *)
let sign = function Call -> 1.0 | Put -> -1.0
