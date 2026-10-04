let rank x =
  let bits = Int64.bits_of_float x in
  let magnitude = Z.of_int64 (Int64.logand bits Int64.max_int) in
  if Float.sign_bit x then Z.neg magnitude else magnitude

let distance a b =
  if Float.is_finite a && Float.is_finite b then
    Some (Z.abs (Z.sub (rank a) (rank b)))
  else None

let ulps a b =
  match distance a b with
  | None -> Float.infinity
  | Some exact ->
      let rounded = Z.to_float exact in
      if Z.compare (Z.of_float rounded) exact < 0 then Float.succ rounded
      else rounded

let within ~budget a b =
  Float.is_finite budget && budget >= 0.
  &&
  match distance a b with
  | None -> false
  | Some d -> Z.compare d (Z.of_float budget) <= 0
