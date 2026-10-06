open Morphiq_fp

(* The pre-native OCaml operation graph, frozen before the native implementation.
   This is a compatibility reference, not the independent financial oracle. *)
let run bands flags state ~first ~last =
  let lo = bands.(0) and diag = bands.(1) and hi = bands.(2) in
  let rhs = bands.(3) and v = bands.(4) and g = bands.(5) in
  let d = bands.(6) and z = bands.(7) and candidate = bands.(8) in
  let mask = flags.(0) and oldmask = flags.(1) in
  let n = Array.length v in
  let exception Stop of int in
  let finite code x = if Float.is_finite x then x else raise (Stop code) in
  state.(4) <- 0;
  let row i =
    state.(4) <- state.(4) + 1;
    match state.(0) with
    | 0 ->
        oldmask.(i) <- mask.(i);
        let pvalue =
          Float.fma lo.(i)
            v.(i - 1)
            (Float.fma diag.(i) v.(i) (Float.fma hi.(i) v.(i + 1) (-.rhs.(i))))
        in
        ignore (finite 1 pvalue);
        mask.(i) <- state.(1) = 1 && pvalue > v.(i) -. g.(i);
        state.(3) <- (state.(3) * 65599 lxor if mask.(i) then i else -i);
        if mask.(i) <> oldmask.(i) then state.(2) <- 1;
        d.(i) <- (if mask.(i) then 1. else diag.(i));
        z.(i) <- (if mask.(i) then g.(i) else rhs.(i))
    | 1 ->
        if d.(i - 1) <= 0. then raise (Stop 2);
        let mult = if mask.(i) then 0. else lo.(i) /. d.(i - 1) in
        let prev_hi = if mask.(i - 1) then 0. else hi.(i - 1) in
        d.(i) <- finite 3 (d.(i) -. (mult *. prev_hi));
        z.(i) <- finite 4 (z.(i) -. (mult *. z.(i - 1)))
    | 2 ->
        if d.(i) <= 0. then raise (Stop 5);
        let next =
          if i = n - 2 || mask.(i) then 0. else hi.(i) *. candidate.(i + 1)
        in
        candidate.(i) <- finite 6 ((z.(i) -. next) /. d.(i))
    | 3 -> v.(i) <- candidate.(i)
    | _ -> invalid_arg "reference phase"
  in
  try
    if state.(0) = 2 then
      for i = first downto last do
        row i
      done
    else
      for i = first to last do
        row i
      done;
    0
  with Stop status -> status
