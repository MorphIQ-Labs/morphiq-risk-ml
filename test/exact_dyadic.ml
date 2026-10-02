(* Exact, per-execution witnesses for the fixed primitive error allowances.
   Q.of_float converts the binary64 value exactly. GMP integer arithmetic
   checks the inequality; no floating discrepancy sets the allowance. *)
module D = Morphiq_risk.Internal.Dd

let q = Q.of_float
let u = q 0x1p-53
let u2 = Q.mul u u
let times n x = Q.mul (Q.of_int n) x
let add_eps = Q.add (times 3 u2) (times 13 (Q.mul u2 u))
let float_eps = times 2 u2
let mul_eps = times 5 u2
let div_eps = Q.mul (Q.make (Z.of_int 49) (Z.of_int 5)) u2
let sqrt_eps = Q.mul (Q.make (Z.of_int 25) (Z.of_int 8)) u2
let quantum = q 0x1p-1074
let value (a : D.t) = Q.add (q a.hi) (q a.lo)

let valid (a : D.t) =
  if not (Float.is_finite a.hi && Float.is_finite a.lo && a.hi +. a.lo = a.hi)
  then
    failwith
      (Printf.sprintf "exact DD witness: nonfinite or overlapping words (%h,%h)"
         a.hi a.lo)

let allowance eps (a : D.t) =
  Q.add
    (Q.div
       (Q.mul eps (Q.add (Q.abs (q a.hi)) (Q.abs (q a.lo))))
       (Q.sub Q.one eps))
    (times 32 quantum)

let check label reference z radius =
  valid z;
  if Q.compare (Q.abs (Q.sub (value z) reference)) radius > 0 then
    failwith ("exact DD witness: " ^ label ^ " exceeds its fixed allowance")

let binary label operation eps a b z =
  valid a;
  valid b;
  check label (operation (value a) (value b)) z (allowance eps z)

let product a b z = check "two_prod" (Q.mul (q a) (q b)) z quantum

let sqrt a z =
  valid a;
  valid z;
  let r = allowance sqrt_eps z in
  let lower = Q.max Q.zero (Q.sub (value z) r) and upper = Q.add (value z) r in
  if
    Q.sign upper < 0
    || Q.compare (Q.mul lower lower) (value a) > 0
    || Q.compare (Q.mul upper upper) (value a) < 0
  then failwith "exact DD witness: sqrt exceeds its fixed allowance"
