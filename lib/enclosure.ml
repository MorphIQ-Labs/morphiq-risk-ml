(* Exact arithmetic identities with configurable finite work. No nominal
   precision is an error bound: all discarded words and tails remain enclosed.
   See docs/runtime-enclosures.md and docs/adaptive-certification.md. *)
module type S = sig
  exception Unresolved of string

  type t = private {
    hi : float;
    lo : float;
    third : float;
    fourth : float;
    error : float;
  }
  (** The real value is within [error] of the unevaluated sum of [words]. All
      fields are finite and [error] is nonnegative. The zero-eliminated lower
      words occupy [third] and [fourth]; zero means an absent trailing word.
      [words] preserves the logical expansion including the first two slots. *)

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

  type interpolation =
    | Endpoint of float
    | Interpolated of t
    | Unresolved_weight

  val linear_interpolate :
    t ->
    lower:float ->
    upper:float ->
    left:float ->
    right:float ->
    interpolation
  (** Original-input convex linear interpolation. Exact endpoints return the
      supplied scalar unchanged. Interior weights must be strictly enclosed in
      (0,1); otherwise [Unresolved_weight]. Arithmetic may raise [Unresolved].
      Returned enclosures own immutable fields; no scratch escapes. *)

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

  type t = {
    hi : float;
    lo : float;
    third : float;
    fourth : float;
    error : float;
  }

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
  let[@inline always] grow expansion length word =
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

  (* Every supported configuration retains at most four nonzero words.
     The first two slots remain present even for exact scalars, as before.
     Zero third/fourth slots encode the absent tail, never discarded values. *)
  let () =
    require (Config.words = 2 || Config.words = 4) "unsupported precision"

  let[@inline always] word_count a =
    if a.fourth <> 0.0 then 4 else if a.third <> 0.0 then 3 else 2

  let[@inline always] word a i =
    match i with
    | 0 -> a.hi
    | 1 -> a.lo
    | 2 -> a.third
    | 3 -> a.fourth
    | _ -> invalid_arg "enclosure word"

  let pack_array expansion length_in error =
    require (Float.is_finite error && error >= 0.0) "invalid enclosure radius";
    (* Before insertion i, the expansion length is at most i. Read term i
       first; grow writes only at or below i, preserving all future terms. *)
    let length = ref 0 in
    for i = 0 to length_in - 1 do
      let input = Float.Array.get expansion i in
      length := grow expansion !length input
    done;
    let kept = min Config.words !length in
    let error = ref error in
    for j = !length - kept - 1 downto 0 do
      let x = Float.Array.get expansion j in
      error := !error +^ abs x
    done;
    require (Float.is_finite !error) "nonfinite enclosure radius";
    let retained i =
      if i < kept then Float.Array.get expansion (!length - i - 1) else 0.0
    in
    {
      hi = retained 0;
      lo = retained 1;
      third = retained 2;
      fourth = retained 3;
      error = !error;
    }

  let[@inline always] exact hi =
    finite hi;
    { hi; lo = 0.0; third = 0.0; fourth = 0.0; error = 0.0 }

  let of_words hi lo =
    let terms = Float.Array.create 2 in
    Float.Array.set terms 0 hi;
    Float.Array.set terms 1 lo;
    pack_array terms (Float.Array.length terms) 0.0

  let words a =
    let tail =
      if a.fourth <> 0.0 then [ a.third; a.fourth ]
      else if a.third <> 0.0 then [ a.third ]
      else []
    in
    a.hi :: a.lo :: tail

  let centre a = { a with error = 0.0 }

  let[@inline always] is_zero a =
    a.hi = 0.0 && a.lo = 0.0 && a.third = 0.0 && a.fourth = 0.0 && a.error = 0.0

  let[@inline always] is_float a x =
    a.hi = x && a.lo = 0.0 && a.third = 0.0 && a.fourth = 0.0 && a.error = 0.0

  let[@inline always] magnitude_from a first =
    let total = ref 0.0 in
    for i = first to word_count a - 1 do
      total := !total +^ abs (word a i)
    done;
    !total

  let[@inline always] centre_magnitude a = magnitude_from a 0
  let[@inline always] magnitude a = centre_magnitude a +^ a.error

  let[@inline always] neg a =
    { a with hi = -.a.hi; lo = -.a.lo; third = -.a.third; fourth = -.a.fourth }

  let[@inline always] add_error a e =
    require (Float.is_finite e && e >= 0.0) "invalid added error";
    let error = a.error +^ e in
    require (Float.is_finite error) "nonfinite enclosure radius";
    { a with error }

  let add_using allocate a b =
    if is_zero a then b
    else if is_zero b then a
    else
      let na = word_count a and nb = word_count b in
      let terms = allocate (na + nb) in
      for i = 0 to na - 1 do
        Float.Array.set terms i (word a i)
      done;
      for i = 0 to nb - 1 do
        Float.Array.set terms (na + i) (word b i)
      done;
      pack_array terms (na + nb) (a.error +^ b.error)

  let[@inline always] add a b = add_using Float.Array.create a b

  let sub_using allocate a b =
    if is_zero a then neg b
    else if is_zero b then a
    else
      let na = word_count a and nb = word_count b in
      let terms = allocate (na + nb) in
      for i = 0 to na - 1 do
        Float.Array.set terms i (word a i)
      done;
      for i = 0 to nb - 1 do
        Float.Array.set terms (na + i) (-.word b i)
      done;
      pack_array terms (na + nb) (a.error +^ b.error)

  (* These scalar specializations insert the same two logical RHS words as
     exact/neg, including padding-zero signs on shortcut results. *)
  let[@inline always] add_float_using allocate a b =
    finite b;
    if is_zero a then exact b
    else if b = 0.0 then a
    else
      let na = word_count a in
      let terms = allocate (na + 2) in
      for i = 0 to na - 1 do
        Float.Array.set terms i (word a i)
      done;
      Float.Array.set terms na b;
      Float.Array.set terms (na + 1) 0.0;
      pack_array terms (na + 2) (a.error +^ 0.0)

  let sub a b = sub_using Float.Array.create a b

  let sub_float a b =
    finite b;
    if is_zero a then neg (exact b)
    else if b = 0.0 then a
    else
      let na = word_count a in
      let terms = Float.Array.create (na + 2) in
      for i = 0 to na - 1 do
        Float.Array.set terms i (word a i)
      done;
      Float.Array.set terms na (-.b);
      Float.Array.set terms (na + 1) (-0.0);
      pack_array terms (Float.Array.length terms) (a.error +^ 0.0)

  let[@inline always] frexp_exponent x =
    let field =
      Int64.(to_int (logand (shift_right_logical (bits_of_float x) 52) 0x7ffL))
    in
    (* For finite normal binary64 x, frexp uses exponent field - 1022.
       Retain the original operation for zero and subnormal inputs. *)
    if field = 0 then snd (Float.frexp x) else field - 1022

  let[@inline always] product_allowance a b =
    (* Both exponents are then at least -484, so their sum is >= -968.
       This exactly implies the existing residual-quantum condition. *)
    if abs a >= 0x1p-485 && abs b >= 0x1p-485 then 0.0
    else
      let ea = frexp_exponent a and eb = frexp_exponent b in
      let error = if ea + eb >= -968 then 0.0 else quantum in
      error

  let mul_using allocate a b =
    if is_zero a || is_zero b then exact 0.0
    else if is_float a 1.0 then b
    else if is_float b 1.0 then a
    else if is_float a (-1.0) then neg b
    else if is_float b (-1.0) then neg a
    else
      let na = word_count a and nb = word_count b in
      let count = 2 * na * nb in
      let terms = allocate count in
      let error = ref 0.0 in
      for i = 0 to na - 1 do
        let x = word a i in
        for j = 0 to nb - 1 do
          let y = word b j in
          let p = x *. y in
          finite p;
          (* The old fold prepended each (p,r) pair. Compute products/errors
             in the original order and store pairs backward to preserve it. *)
          let k = count - (2 * ((i * nb) + j)) - 2 in
          Float.Array.set terms k p;
          if x = 0.0 || y = 0.0 || abs x = 1.0 || abs y = 1.0 then (
            Float.Array.set terms (k + 1) 0.0;
            error := !error +^ 0.0)
          else
            let r = Float.fma x y (-.p) in
            Float.Array.set terms (k + 1) r;
            error := !error +^ product_allowance x y
        done
      done;
      let input = (centre_magnitude a *^ b.error) +^ (magnitude b *^ a.error) in
      pack_array terms count (!error +^ input)

  let[@inline always] mul a b = mul_using Float.Array.create a b

  let[@inline always] mul_float_using allocate a b =
    finite b;
    if is_zero a || b = 0.0 then exact 0.0
    else if is_float a 1.0 then exact b
    else if b = 1.0 then a
    else if is_float a (-1.0) then neg (exact b)
    else if b = -1.0 then neg a
    else
      let na = word_count a in
      let count = 4 * na in
      let terms = allocate count in
      let error = ref 0.0 in
      for i = 0 to na - 1 do
        let x = word a i in
        for j = 0 to 1 do
          let y = if j = 0 then b else 0.0 in
          let p = x *. y in
          finite p;
          let k = count - (2 * ((i * 2) + j)) - 2 in
          Float.Array.set terms k p;
          if x = 0.0 || y = 0.0 || abs x = 1.0 || abs y = 1.0 then (
            Float.Array.set terms (k + 1) 0.0;
            error := !error +^ 0.0)
          else
            let r = Float.fma x y (-.p) in
            Float.Array.set terms (k + 1) r;
            error := !error +^ product_allowance x y
        done
      done;
      (* An exact scalar's radius is zero and magnitude is abs b. Keep the
         product-pair and outward radius accumulation order of mul. *)
      let input = (centre_magnitude a *^ 0.0) +^ (abs b *^ a.error) in
      pack_array terms count (!error +^ input)

  let[@inline always] mul_float a b = mul_float_using Float.Array.create a b

  let div_float_using allocate a b =
    require (Float.is_finite b && b <> 0.0) "invalid scalar denominator";
    if b = 1.0 then a
    else if b = -1.0 then neg a
    else if is_zero a then exact 0.0
    else
      let remainder = ref a and quotient = ref (exact 0.0) in
      for _ = 1 to Config.words do
        let q = !remainder.hi /. b in
        quotient := add_float_using allocate !quotient q;
        remainder :=
          sub_using allocate !remainder (mul_float_using allocate (exact q) b)
      done;
      add_error !quotient (magnitude !remainder /^ abs b)

  let div_float a b =
    require (Float.is_finite b && b <> 0.0) "invalid scalar denominator";
    if b = 1.0 then a
    else if b = -1.0 then neg a
    else if is_zero a then exact 0.0
    else
      (* A quotient proposal is an exact scalar: its product needs eight terms.
         Quotient addition uses <=6 and remainder subtraction <=8 in either
         precision. Packing copies retained words; no enclosure borrows scratch. *)
      let scratch = Float.Array.create 8 in
      let allocate count =
        require (count <= 8) "scalar quotient scratch bound";
        scratch
      in
      div_float_using allocate a b

  let div a b =
    require (b.hi <> 0.0) "unresolved denominator";
    if b.lo = 0.0 && b.third = 0.0 && b.fourth = 0.0 && b.error = 0.0 then
      div_float a b.hi
    else
      let terms = Float.Array.create (word_count b - 1) in
      for i = 1 to word_count b - 1 do
        Float.Array.set terms (i - 1) (word b i)
      done;
      let rho =
        div_float (pack_array terms (Float.Array.length terms) b.error) b.hi
      in
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
    let scaled = Float.Array.create (word_count a) in
    for i = 0 to word_count a - 1 do
      let input = word a i in
      let result = Float.ldexp input k in
      if input <> 0.0 && abs result < Float.min_float then
        error := !error +^ quantum;
      Float.Array.set scaled i result
    done;
    pack_array scaled (Float.Array.length scaled) !error

  let sign a =
    if is_zero a then Zero
    else if a.lo = 0.0 && a.third = 0.0 && a.fourth = 0.0 && a.error = 0.0 then
      if a.hi > 0.0 then Positive else Negative
    else
      let rest = magnitude_from a 1 +^ a.error in
      if down (a.hi -. rest) > 0.0 then Positive
      else if up (a.hi +. rest) < 0.0 then Negative
      else Indeterminate

  let compare_float a b = sign (sub_float a b)
  let error_of_float a b = magnitude (sub_float a b)

  type interpolation =
    | Endpoint of float
    | Interpolated of t
    | Unresolved_weight

  let linear_interpolate point ~lower ~upper ~left ~right =
    if compare_float point lower = Zero then Endpoint left
    else if compare_float point upper = Zero then Endpoint right
    else
      let width = sub (exact upper) (exact lower) in
      let weight = div (sub point (exact lower)) width in
      match (compare_float weight 0., compare_float weight 1.) with
      | Positive, Negative ->
          Interpolated
            (add
               (mul (sub (exact 1.) weight) (exact left))
               (mul weight (exact right)))
      | _ -> Unresolved_weight

  let sqrt a =
    if is_zero a then a
    else (
      require (sign a = Positive) "square root interval not positive";
      let exponent = (snd (Float.frexp a.hi) - 1) asr 1 in
      let a = scale a (-2 * exponent) in
      let result = ref (exact (Float.sqrt a.hi)) in
      for _ = 1 to 3 do
        let q = centre !result in
        let lower = down (q.hi -. magnitude_from q 1) in
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
      (* Every operation fully overwrites its used prefix before packing copies
         retained fields into an immutable result. Product pairs need <=2*w*w,
         scalar products <=4*w, sums <=2*w, and quotient suboperations <=8.
         No result borrows this call-owned array, including nested arguments. *)
      let capacity = max 8 (2 * Config.words * Config.words) in
      let scratch = Float.Array.create capacity in
      let allocate count =
        require (count <= capacity) "exponential scratch bound";
        scratch
      in
      let add a b = add_using allocate a b
      and mul a b = mul_using allocate a b
      and mul_float a b = mul_float_using allocate a b
      and div_float a b = div_float_using allocate a b in
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
