type failure = Non_convergence | Numerical_failure

let midpoint lower upper =
  let l = Int64.bits_of_float lower and h = Int64.bits_of_float upper in
  Int64.float_of_bits (Int64.add l (Int64.div (Int64.sub h l) 2L))

let solve ?(max_iterations = 256) ~value ~proposal ~target ~lower ~upper
    ~initial () =
  if
    max_iterations < 0
    || not
         (Float.is_finite target && Float.is_finite lower
        && Float.is_finite upper && lower >= 0.0 && upper > lower)
  then Error Numerical_failure
  else
    (* Canonicalize negative zero before using the ordered positive encoding. *)
    let lower = if lower = 0.0 then 0.0 else lower in
    let vl = value lower and vh = value upper in
    if
      not
        (Float.is_finite vl && Float.is_finite vh && vl <= target
       && target <= vh)
    then Error Numerical_failure
    else
      let rec go n lower vl upper vh candidate =
        if vl = target then Ok lower
        else if vh = target then Ok upper
        else if Float.succ lower >= upper then
          Ok (if target -. vl <= vh -. target then lower else upper)
        else if n >= max_iterations then Error Non_convergence
        else
          let candidate =
            if n land 3 = 3 then midpoint lower upper
            else if candidate > lower && candidate < upper then candidate
            else
              let middle = lower +. (0.5 *. (upper -. lower)) in
              if middle > lower && middle < upper then middle
              else midpoint lower upper
          in
          let v = value candidate in
          if not (Float.is_finite v) then Error Numerical_failure
          else if v = target then Ok candidate
          else
            let next = proposal candidate v in
            (* A rounded Newton proposal can stagnate while the global bracket
               is still wide. Evaluate the adjacent float toward the target;
               only its actual residual, never the small step, can finish. *)
            let neighbour =
              if v < target then Float.succ candidate else Float.pred candidate
            in
            if next >= Float.pred candidate && next <= Float.succ candidate then
              let vn = value neighbour in
              if not (Float.is_finite vn) then Error Numerical_failure
              else if
                (v < target && vn >= target) || (v > target && vn <= target)
              then
                Ok
                  (if Float.abs (v -. target) <= Float.abs (vn -. target) then
                     candidate
                   else neighbour)
              else if v < target then go (n + 1) neighbour vn upper vh next
              else go (n + 1) lower vl neighbour vn next
            else if v < target then go (n + 1) candidate v upper vh next
            else go (n + 1) lower vl candidate v next
      in
      go 0 lower vl upper vh initial

let refine ~value ~target ~candidate =
  if not (Float.is_finite candidate && candidate > 0.0 && Float.is_finite target)
  then Error Numerical_failure
  else
    let v = value candidate in
    if not (Float.is_finite v) then Error Numerical_failure
    else if v = target then Ok candidate
    else
      let lower = Float.pred candidate and upper = Float.succ candidate in
      let vl = value lower and vh = value upper in
      if
        Float.is_finite vl && Float.is_finite vh && vl <= target && target <= vh
      then
        if v < target then
          Ok (if target -. v <= vh -. target then candidate else upper)
        else Ok (if target -. vl <= v -. target then lower else candidate)
      else
        solve ~value
          ~proposal:(fun _ _ -> Float.nan)
          ~target ~lower:(candidate *. 0.5) ~upper:(candidate *. 2.0)
          ~initial:candidate ()
