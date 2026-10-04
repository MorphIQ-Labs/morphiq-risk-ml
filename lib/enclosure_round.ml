(* Resolve a nearest-even binary64 cell from the entire runtime enclosure. *)
module E = Enclosure

let even x = Int64.logand (Int64.bits_of_float x) 1L = 0L

let nearest ?(exponent = 0) value =
  let unscale x =
    if exponent = 0 then E.exact x else E.scale (E.exact x) (-exponent)
  in
  let midpoint lower upper =
    let lower = unscale lower and upper = unscale upper in
    E.add lower (E.scale (E.sub upper lower) (-1))
  in
  let accepts candidate =
    if not (Float.is_finite candidate) then false
    else if E.sign (E.sub value (unscale candidate)) = E.Zero then true
    else
      let lower = Float.pred candidate and upper = Float.succ candidate in
      if not (Float.is_finite lower && Float.is_finite upper) then false
      else
        let left = E.sign (E.sub value (midpoint lower candidate))
        and right = E.sign (E.sub value (midpoint candidate upper)) in
        (left = E.Positive || (left = E.Zero && even candidate))
        && (right = E.Negative || (right = E.Zero && even candidate))
  in
  let proposal = Float.ldexp value.hi exponent in
  List.find_opt accepts [ proposal; Float.pred proposal; Float.succ proposal ]
