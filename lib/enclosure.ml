(* Independent runtime enclosures. Every radius comes from IEEE rounding,
   an exact residual, or an explicit analytic remainder. See the derivation
   in docs/runtime-enclosures.md; no empirical kernel envelope is a premise. *)
exception Unresolved of string

type t = { hi : float; lo : float; error : float }
type sign = Negative | Zero | Positive | Indeterminate

let require condition why = if not condition then raise (Unresolved why)
let finite x = require (Float.is_finite x) "nonfinite enclosure arithmetic"
let quantum = 0x1p-1074
let up x = Float.next_after x Float.infinity
let down x = Float.next_after x Float.neg_infinity
let abs = Float.abs
let ( +^ ) a b = if a = 0.0 then b else if b = 0.0 then a else up (a +. b)
let ( *^ ) a b = if a = 0.0 || b = 0.0 then 0.0 else up (a *. b)
let ( /^ ) a b = if a = 0.0 then 0.0 else up (a /. b)

let rounding v =
  finite v;
  Float.max quantum (0.5 *. (Float.succ (abs v) -. abs v))

let two_sum a b =
  let s = a +. b in
  let bb = s -. a in
  let aa = s -. bb in
  let da = a -. aa and db = b -. bb in
  let low = da +. db in
  List.iter finite [ s; bb; aa; da; db; low ];
  (s, low)

let make hi lo error =
  require (Float.is_finite error && error >= 0.0) "invalid enclosure radius";
  let hi, lo = two_sum hi lo in
  { hi; lo; error }

let exact hi =
  finite hi;
  { hi; lo = 0.0; error = 0.0 }

let of_words hi lo = make hi lo 0.0
let is_zero a = a.hi = 0.0 && a.lo = 0.0 && a.error = 0.0
let is_float a x = a.hi = x && a.lo = 0.0 && a.error = 0.0
let centre_magnitude a = abs a.hi +^ abs a.lo
let magnitude a = centre_magnitude a +^ a.error
let neg a = { a with hi = -.a.hi; lo = -.a.lo }

let add_error a e =
  require (e >= 0.0) "negative added error";
  make a.hi a.lo (a.error +^ e)

let add a b =
  if is_zero a then b
  else if is_zero b then a
  else
    let hi, residual = two_sum a.hi b.hi in
    let low, e1 = two_sum a.lo b.lo in
    let low, e2 = two_sum residual low in
    make hi low (a.error +^ b.error +^ abs e1 +^ abs e2)

let sub a b = add a (neg b)

let product a b =
  let p = a *. b in
  finite p;
  if a = 0.0 || b = 0.0 || abs a = 1.0 || abs b = 1.0 then (p, 0.0, 0.0)
  else
    let r = Float.fma a b (-.p) in
    (p, r, rounding r)

let scalar_product a b =
  let p, r, e = product a b in
  (p, abs r +^ e)

let mul a b =
  if is_zero a || is_zero b then exact 0.0
  else if is_float a 1.0 then b
  else if is_float b 1.0 then a
  else if is_float a (-1.0) then neg b
  else if is_float b (-1.0) then neg a
  else
    let hi, residual, error = product a.hi b.hi in
    let low, error =
      List.fold_left
        (fun (low, error) (x, y) ->
          let p, ep = scalar_product x y in
          let low, el = two_sum low p in
          (low, error +^ ep +^ abs el))
        (residual, error)
        [ (a.hi, b.lo); (a.lo, b.hi); (a.lo, b.lo) ]
    in
    let input = (centre_magnitude a *^ b.error) +^ (magnitude b *^ a.error) in
    make hi low (error +^ input)

let mul_float a b = mul a (exact b)

let div_float a b =
  require (Float.is_finite b && b <> 0.0) "invalid scalar denominator";
  if b = 1.0 then a
  else if b = -1.0 then neg a
  else if is_zero a then exact 0.0
  else
    let hi = a.hi /. b in
    finite hi;
    let r = Float.fma (-.hi) b a.hi in
    let er = rounding r in
    let rem, er_add = two_sum r a.lo in
    let low = rem /. b in
    let er_div = if rem = 0.0 then 0.0 else rounding low in
    make hi low (((a.error +^ er +^ abs er_add) /^ abs b) +^ er_div)

let div a b =
  require (b.hi <> 0.0) "unresolved denominator";
  if b.lo = 0.0 && b.error = 0.0 then div_float a b.hi
  else
    let rho = div_float (make b.lo 0.0 b.error) b.hi in
    let r = magnitude rho in
    require (r < 0.5) "denominator uncertainty";
    let quotient = div_float a b.hi in
    let inverse = add (sub (exact 1.0) rho) (mul rho rho) in
    let remainder = r *^ r *^ r /^ down (1.0 -. r) in
    add_error (mul quotient inverse) (magnitude quotient *^ remainder)

let scale a k =
  let hi = Float.ldexp a.hi k and lo = Float.ldexp a.lo k in
  let loss input result =
    if input <> 0.0 && abs result < Float.min_float then quantum else 0.0
  in
  let error = if a.error = 0.0 then 0.0 else up (Float.ldexp a.error k) in
  make hi lo (error +^ loss a.hi hi +^ loss a.lo lo)

let sign a =
  if is_zero a then Zero
  else if a.error = 0.0 then if a.hi > 0.0 then Positive else Negative
  else if down (down (a.hi -. abs a.lo) -. a.error) > 0.0 then Positive
  else if up (up (a.hi +. abs a.lo) +. a.error) < 0.0 then Negative
  else Indeterminate

let compare_float a b = sign (sub a (exact b))
let error_of_float a b = magnitude (sub a (exact b))

let sqrt a =
  if is_zero a then a
  else (
    require (sign a = Positive) "square root interval not positive";
    let exponent = (snd (Float.frexp a.hi) - 1) asr 1 in
    let a = scale a (-2 * exponent) in
    let q = Float.sqrt a.hi in
    let d = sub a (mul (exact q) (exact q)) in
    let correction = div_float d (2.0 *. q) in
    let ratio = magnitude d /^ q in
    let remainder = ratio *^ ratio /^ (2.0 *. q) in
    scale (add_error (add (exact q) correction) remainder) exponent)

let exponential ~minus_one a =
  if is_zero a then exact (if minus_one then 0.0 else 1.0)
  else (
    require (magnitude a <= 256.0) "exponential enclosure domain";
    let r = scale a (-10) in
    let term = ref (exact 1.0) in
    let sum = ref (exact (if minus_one then 0.0 else 1.0)) in
    for n = 1 to 24 do
      term := div_float (mul !term r) (float n);
      sum := add !sum !term
    done;
    let omitted = div_float (mul !term r) 25.0 in
    let ratio = magnitude r /^ 26.0 in
    let tail = magnitude omitted /^ down (1.0 -. ratio) in
    let result = ref (add_error !sum tail) in
    for _ = 1 to 10 do
      result :=
        if minus_one then add (mul_float !result 2.0) (mul !result !result)
        else mul !result !result
    done;
    !result)

let exp a = exponential ~minus_one:false a
let expm1 a = exponential ~minus_one:true a

let twice_atanh z =
  let radius = magnitude z in
  require (radius < 0.5) "logarithm reduction uncertainty";
  let z2 = mul z z in
  let term = ref z and sum = ref (exact 0.0) in
  for n = 0 to 63 do
    sum := add !sum (div_float !term (float ((2 * n) + 1)));
    term := mul !term z2
  done;
  let denominator = down (129.0 *. down (1.0 -. (radius *^ radius))) in
  let tail = 2.0 *^ magnitude !term /^ denominator in
  add_error (mul_float !sum 2.0) tail

let ln2 = twice_atanh (div_float (exact 1.0) 3.0)

let log a =
  require (sign a = Positive) "logarithm interval not positive";
  let exponent = snd (Float.frexp a.hi) - 1 in
  let m = scale a (-exponent) in
  let z = div (sub m (exact 1.0)) (add m (exact 1.0)) in
  add (twice_atanh z) (mul_float ln2 (float exponent))
