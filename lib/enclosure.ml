(* Exact arithmetic identities with configurable finite work. No nominal
   precision is an error bound: all discarded words and tails remain enclosed.
   See docs/runtime-enclosures.md and docs/adaptive-certification.md. *)
module type S = sig
  exception Unresolved of string

  type t = private { hi : float; lo : float; tail : float list; error : float }
  (** The real value is within [error] of the unevaluated sum of [words]. All
      fields are finite and [error] is nonnegative. *)

  type sign = Negative | Zero | Positive | Indeterminate

  val exact : float -> t
  val of_words : float -> float -> t
  val words : t -> float list

  val centre : t -> t
  (** Exact retained expansion, used only as a new arithmetic proposal. *)

  val add : t -> t -> t
  val sub : t -> t -> t
  val neg : t -> t
  val mul : t -> t -> t
  val mul_float : t -> float -> t
  val div : t -> t -> t
  val div_float : t -> float -> t
  val scale : t -> int -> t
  val sqrt : t -> t
  val exp : t -> t
  val expm1 : t -> t
  val log : t -> t
  val magnitude : t -> float
  val sign : t -> sign
  val compare_float : t -> float -> sign
  val error_of_float : t -> float -> float

  val add_error : t -> float -> t
  (** Enlarge a radius by a proved nonnegative error allowance. *)
end

module Make (Config : sig
  val words : int
  val exp_terms : int
  val log_terms : int
end) =
struct
  exception Unresolved of string

  type t = { hi : float; lo : float; tail : float list; error : float }
  type sign = Negative | Zero | Positive | Indeterminate

  let[@inline always] require condition why =
    if not condition then raise (Unresolved why)

  let[@inline always] finite x =
    require (Float.is_finite x) "nonfinite enclosure arithmetic"

  let quantum = 0x1p-1074
  let up x = Float.next_after x Float.infinity
  let down x = Float.next_after x Float.neg_infinity
  let abs = Float.abs
  let ( +^ ) a b = if a = 0.0 then b else if b = 0.0 then a else up (a +. b)
  let ( *^ ) a b = if a = 0.0 || b = 0.0 then 0.0 else up (a *. b)
  let ( /^ ) a b = if a = 0.0 then 0.0 else up (a /. b)

  let[@inline always] two_sum a b =
    let s = a +. b in
    (* FastTwoSum requires the larger-magnitude operand first. Both branches
       recover the exact residual of the same rounded sum. A nonfinite input
       or intermediate propagates to low, so this check covers the whole graph. *)
    let low = if abs a >= abs b then b -. (s -. a) else a -. (s -. b) in
    finite low;
    (s, low)

  (* Exact grow-expansion in private scratch, in increasing-magnitude order.
     At step j, used <= j: writing a residual cannot overwrite an unread term.
     Each inserted word increases length by at most one. *)
  let grow expansion length word =
    let carry = ref word and used = ref 0 in
    for j = 0 to length - 1 do
      let sum, residual = two_sum !carry (Float.Array.get expansion j) in
      if residual <> 0.0 then (
        Float.Array.set expansion !used residual;
        incr used);
      carry := sum
    done;
    if !carry <> 0.0 then (
      Float.Array.set expansion !used !carry;
      incr used);
    !used

  let pack terms error =
    require (Float.is_finite error && error >= 0.0) "invalid enclosure radius";
    (* No grow can retain more words than have been inserted. Scratch never
       escapes this call, and all indexing remains checked. *)
    let expansion = Float.Array.create (List.length terms) in
    let length = List.fold_left (grow expansion) 0 terms in
    let rec take n kept error j =
      if j < 0 then (List.rev kept, error)
      else
        let x = Float.Array.get expansion j in
        if n > 0 then take (n - 1) (x :: kept) error (j - 1)
        else take 0 kept (error +^ abs x) (j - 1)
    in
    let words, error = take Config.words [] error (length - 1) in
    require (Float.is_finite error) "nonfinite enclosure radius";
    match words with
    | [] -> { hi = 0.0; lo = 0.0; tail = []; error }
    | [ hi ] -> { hi; lo = 0.0; tail = []; error }
    | hi :: lo :: tail -> { hi; lo; tail; error }

  let exact hi =
    finite hi;
    { hi; lo = 0.0; tail = []; error = 0.0 }

  let of_words hi lo = pack [ hi; lo ] 0.0
  let words a = a.hi :: a.lo :: a.tail
  let centre a = { a with error = 0.0 }
  let is_zero a = a.hi = 0.0 && a.lo = 0.0 && a.tail = [] && a.error = 0.0
  let is_float a x = a.hi = x && a.lo = 0.0 && a.tail = [] && a.error = 0.0
  let sum_abs terms = List.fold_left (fun total x -> total +^ abs x) 0.0 terms
  let centre_magnitude a = sum_abs (words a)
  let magnitude a = centre_magnitude a +^ a.error

  let neg a =
    { a with hi = -.a.hi; lo = -.a.lo; tail = List.map (fun x -> -.x) a.tail }

  let add_error a e =
    require (Float.is_finite e && e >= 0.0) "invalid added error";
    let error = a.error +^ e in
    require (Float.is_finite error) "nonfinite enclosure radius";
    { a with error }

  let add a b =
    if is_zero a then b
    else if is_zero b then a
    else pack (words a @ words b) (a.error +^ b.error)

  let sub a b = add a (neg b)

  let[@inline always] product_allowance a b =
    (* Both exponents are then at least -484, so their sum is >= -968.
       This exactly implies the existing residual-quantum condition. *)
    if abs a >= 0x1p-485 && abs b >= 0x1p-485 then 0.0
    else
      let ea = snd (Float.frexp a) and eb = snd (Float.frexp b) in
      let error = if ea + eb >= -968 then 0.0 else quantum in
      error

  let product a b =
    let p = a *. b in
    finite p;
    if a = 0.0 || b = 0.0 || abs a = 1.0 || abs b = 1.0 then (p, 0.0, 0.0)
    else
      let r = Float.fma a b (-.p) in
      (* Each input is an integer multiple of 2^(frexp_exponent-53).
       If the product quantum is representable, the p-bit residual is exact.
       Otherwise only underflow can round it; retain a full quantum. *)
      (p, r, product_allowance a b)

  let mul a b =
    if is_zero a || is_zero b then exact 0.0
    else if is_float a 1.0 then b
    else if is_float b 1.0 then a
    else if is_float a (-1.0) then neg b
    else if is_float b (-1.0) then neg a
    else
      let terms, error =
        List.fold_left
          (fun state x ->
            List.fold_left
              (fun (terms, error) y ->
                let p, r, e = product x y in
                (p :: r :: terms, error +^ e))
              state (words b))
          ([], 0.0) (words a)
      in
      let input = (centre_magnitude a *^ b.error) +^ (magnitude b *^ a.error) in
      pack terms (error +^ input)

  let mul_float a b = mul a (exact b)

  let div_float a b =
    require (Float.is_finite b && b <> 0.0) "invalid scalar denominator";
    if b = 1.0 then a
    else if b = -1.0 then neg a
    else if is_zero a then exact 0.0
    else
      let remainder = ref a and quotient = ref (exact 0.0) in
      for _ = 1 to Config.words do
        let q = exact (!remainder.hi /. b) in
        quotient := add !quotient q;
        remainder := sub !remainder (mul_float q b)
      done;
      add_error !quotient (magnitude !remainder /^ abs b)

  let div a b =
    require (b.hi <> 0.0) "unresolved denominator";
    if b.lo = 0.0 && b.tail = [] && b.error = 0.0 then div_float a b.hi
    else
      let rho = div_float (pack (b.lo :: b.tail) b.error) b.hi in
      let r = magnitude rho in
      require (r < 0.5) "denominator uncertainty";
      let quotient = div_float a b.hi in
      let power = ref (exact 1.0) and inverse = ref (exact 1.0) in
      for _ = 1 to Config.words - 1 do
        power := mul !power (neg rho);
        inverse := add !inverse !power
      done;
      let tail = ref 1.0 in
      for _ = 1 to Config.words do
        tail := !tail *^ r
      done;
      let remainder = !tail /^ down (1.0 -. r) in
      add_error (mul quotient !inverse) (magnitude quotient *^ remainder)

  let scale a k =
    let error =
      ref (if a.error = 0.0 then 0.0 else up (Float.ldexp a.error k))
    in
    let scaled =
      List.map
        (fun input ->
          let result = Float.ldexp input k in
          if input <> 0.0 && abs result < Float.min_float then
            error := !error +^ quantum;
          result)
        (words a)
    in
    pack scaled !error

  let sign a =
    if is_zero a then Zero
    else if a.lo = 0.0 && a.tail = [] && a.error = 0.0 then
      if a.hi > 0.0 then Positive else Negative
    else
      let rest = sum_abs (a.lo :: a.tail) +^ a.error in
      if down (a.hi -. rest) > 0.0 then Positive
      else if up (a.hi +. rest) < 0.0 then Negative
      else Indeterminate

  let compare_float a b = sign (sub a (exact b))
  let error_of_float a b = magnitude (sub a (exact b))

  let sqrt a =
    if is_zero a then a
    else (
      require (sign a = Positive) "square root interval not positive";
      let exponent = (snd (Float.frexp a.hi) - 1) asr 1 in
      let a = scale a (-2 * exponent) in
      let result = ref (exact (Float.sqrt a.hi)) in
      for _ = 1 to 3 do
        let q = centre !result in
        let lower = down (q.hi -. sum_abs (q.lo :: q.tail)) in
        require (lower > 0.0) "square root proposal not positive";
        let d = sub a (mul q q) in
        let correction = div d (mul_float q 2.0) in
        let ratio = magnitude d /^ lower in
        let remainder = ratio *^ ratio /^ (2.0 *. lower) in
        result := add_error (add q correction) remainder
      done;
      scale !result exponent)

  let exponential ~minus_one a =
    if is_zero a then exact (if minus_one then 0.0 else 1.0)
    else (
      require (magnitude a <= 256.0) "exponential enclosure domain";
      let r = scale a (-10) in
      let term = ref (exact 1.0) in
      let sum = ref (exact (if minus_one then 0.0 else 1.0)) in
      for n = 1 to Config.exp_terms do
        term := div_float (mul !term r) (float n);
        sum := add !sum !term
      done;
      let omitted = div_float (mul !term r) (float (Config.exp_terms + 1)) in
      let ratio = magnitude r /^ float (Config.exp_terms + 2) in
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
    for n = 0 to Config.log_terms - 1 do
      sum := add !sum (div_float !term (float ((2 * n) + 1)));
      term := mul !term z2
    done;
    let denominator =
      down
        (float ((2 * Config.log_terms) + 1) *. down (1.0 -. (radius *^ radius)))
    in
    let tail = 2.0 *^ magnitude !term /^ denominator in
    add_error (mul_float !sum 2.0) tail

  let ln2 = twice_atanh (div_float (exact 1.0) 3.0)

  let log a =
    require (sign a = Positive) "logarithm interval not positive";
    let exponent = snd (Float.frexp a.hi) - 1 in
    let m = scale a (-exponent) in
    let z = div (sub m (exact 1.0)) (add m (exact 1.0)) in
    add (twice_atanh z) (mul_float ln2 (float exponent))
end

include Make (struct
  let words = 4
  let exp_terms = 48
  let log_terms = 96
end)

module Fast = Make (struct
  let words = 2
  let exp_terms = 16
  let log_terms = 32
end)
