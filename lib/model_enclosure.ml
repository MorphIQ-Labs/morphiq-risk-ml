(* Independent real-model enclosures, derived in docs/model-enclosures.md. *)
module E = Enclosure

let one = E.exact 1.0
let zero = E.exact 0.0
let require p message = if not p then raise (E.Unresolved message)
let up = Float.succ
let down = Float.pred

let hull a b =
  let centre = E.centre a in
  E.add_error centre (Float.max a.error (E.magnitude (E.sub b centre)))

let positive_part a =
  match E.sign a with
  | E.Positive -> a
  | E.Negative | E.Zero -> zero
  | E.Indeterminate -> hull zero a

let atan x =
  let x2 = E.mul x x in
  let term = ref x and sum = ref zero in
  for n = 0 to 63 do
    let next = E.div_float !term (float ((2 * n) + 1)) in
    sum := if n land 1 = 0 then E.add !sum next else E.sub !sum next;
    term := E.mul !term x2
  done;
  E.add_error !sum (up (E.magnitude !term /. 129.0))

let pi =
  E.sub
    (E.mul_float (atan (E.div_float one 5.0)) 16.0)
    (E.mul_float (atan (E.div_float one 239.0)) 4.0)

let inv_sqrt_2pi = E.div one (E.sqrt (E.mul_float pi 2.0))

let exp a =
  if E.magnitude a <= 256.0 then E.exp a
  else (
    require (E.magnitude a <= 1024.0) "model exponential enclosure domain";
    let quarter = E.exp (E.scale a (-2)) in
    let half = E.mul quarter quarter in
    E.mul half half)

let beyond_tail x =
  match E.compare_float x 40.0 with E.Positive | E.Zero -> true | _ -> false

let negligible_tail = E.add_error zero 0x1p-1074

let pdf x =
  if beyond_tail x || beyond_tail (E.neg x) then negligible_tail
  else E.mul inv_sqrt_2pi (exp (E.scale (E.neg (E.mul x x)) (-1)))

let series_cdf x =
  let x2 = E.mul x x in
  let term = ref x and sum = ref zero in
  for n = 0 to 95 do
    sum := E.add !sum !term;
    term := E.div_float (E.mul !term x2) (float ((2 * n) + 3))
  done;
  let ratio = up (E.magnitude x2 /. 195.0) in
  require (ratio < 1.0) "normal series remainder domain";
  let tail = up (E.magnitude !term /. down (1.0 -. ratio)) in
  E.add (E.exact 0.5) (E.mul (pdf x) (E.add_error !sum tail))

let mills x =
  require (E.sign x = E.Positive) "Mills ratio requires positive interval";
  let convergent n =
    let tail = ref zero in
    for k = n downto 1 do
      tail := E.div (E.exact (float k)) (E.add x !tail)
    done;
    E.div one (E.add x !tail)
  in
  hull (convergent 128) (convergent 129)

let cdf x =
  if beyond_tail x then E.sub one negligible_tail
  else if beyond_tail (E.neg x) then negligible_tail
  else if E.magnitude x <= 4.0 then series_cdf x
  else
    match E.sign x with
    | E.Positive -> E.sub one (E.mul (pdf x) (mills x))
    | E.Negative ->
        let y = E.neg x in
        E.mul (pdf y) (mills y)
    | E.Zero -> E.exact 0.5
    | E.Indeterminate -> raise (E.Unresolved "normal argument sign unresolved")

type black = {
  asset : E.t;
  cash : E.t;
  distance : E.t;
  x : E.t;
  root_time : E.t;
}

type normal = { discount : E.t; distance : E.t; root_time : E.t }
type t = Black of black | Normal of normal

let discount rate time = exp (E.neg (E.mul (E.exact rate) (E.exact time)))

let black ~spot ~spot_low ~strike ~strike_low ~time ~rate ~yield =
  require (Float.is_finite time && time >= 0.0) "invalid model maturity";
  let spot = E.of_words spot spot_low
  and strike = E.of_words strike strike_low in
  require
    (E.sign spot = E.Positive && E.sign strike = E.Positive)
    "nonpositive lognormal coordinates";
  let dr = discount rate time and dq = discount yield time in
  let asset = E.mul spot dq and cash = E.mul strike dr in
  let distance =
    if rate = yield then E.mul (E.sub spot strike) dr else E.sub asset cash
  in
  let log_ratio = if spot = strike then zero else E.log (E.div spot strike) in
  let carry = E.mul (E.sub (E.exact rate) (E.exact yield)) (E.exact time) in
  Black
    {
      asset;
      cash;
      distance;
      x = E.add log_ratio carry;
      root_time = E.sqrt (E.exact time);
    }

let normal ~forward ~strike ~time ~rate =
  require (Float.is_finite time && time >= 0.0) "invalid model maturity";
  Normal
    {
      discount = discount rate time;
      distance = E.sub (E.exact forward) (E.exact strike);
      root_time = E.sqrt (E.exact time);
    }

let bounds model side =
  let theta = Side.sign side in
  match model with
  | Black c ->
      ( positive_part (E.mul_float c.distance theta),
        Some (if side = Side.Call then c.asset else c.cash) )
  | Normal c ->
      (E.mul c.discount (positive_part (E.mul_float c.distance theta)), None)

let price_enclosed model side sigma =
  require
    (E.sign sigma = E.Positive || E.sign sigma = E.Zero)
    "unresolved model volatility";
  let theta = Side.sign side in
  let root_time =
    match model with Black c -> c.root_time | Normal c -> c.root_time
  in
  if E.sign sigma = E.Zero || E.sign root_time = E.Zero then
    fst (bounds model side)
  else
    let s = E.mul root_time sigma in
    require (E.sign s = E.Positive) "total volatility interval not positive";
    match model with
    | Black c ->
        let h = E.div c.x s and half = E.scale s (-1) in
        let d1 = E.mul_float (E.add h half) theta
        and d2 = E.mul_float (E.sub h half) theta in
        E.mul_float
          (E.sub (E.mul c.asset (cdf d1)) (E.mul c.cash (cdf d2)))
          theta
    | Normal c ->
        let d = E.div c.distance s in
        E.mul c.discount
          (E.add
             (E.mul (E.mul_float c.distance theta) (cdf (E.mul_float d theta)))
             (E.mul s (pdf d)))

let price model side sigma = price_enclosed model side (E.exact sigma)

let inverse_residual model side quote =
  if quote = 0.0 then fun sigma -> price_enclosed model side sigma
  else
    let log_quote = E.log (E.exact quote) in
    let gaussian log_weight d =
      E.mul inv_sqrt_2pi (exp (E.sub log_weight (E.scale (E.mul d d) (-1))))
    in
    let weighted_cdf log_weight d =
      if E.magnitude d <= 4.0 then E.mul (exp log_weight) (cdf d)
      else
        match E.sign d with
        | E.Negative -> E.mul (gaussian log_weight d) (mills (E.neg d))
        | E.Positive ->
            E.sub (exp log_weight) (E.mul (gaussian log_weight d) (mills d))
        | E.Zero | E.Indeterminate ->
            raise (E.Unresolved "weighted normal sign unresolved")
    in
    let intrinsic = E.div_float (fst (bounds model side)) quote in
    match model with
    | Black c ->
        let log_asset = E.sub (E.log c.asset) log_quote
        and log_cash = E.sub (E.log c.cash) log_quote in
        fun sigma ->
          if E.sign sigma = E.Zero then E.sub intrinsic one
          else
            let s = E.mul c.root_time sigma in
            let h = E.div c.x s and half = E.scale s (-1) in
            let theta = Side.sign side in
            let d1 = E.mul_float (E.add h half) theta
            and d2 = E.mul_float (E.sub h half) theta in
            E.sub
              (E.mul_float
                 (E.sub (weighted_cdf log_asset d1) (weighted_cdf log_cash d2))
                 theta)
              one
    | Normal c ->
        let base = E.sub (E.log c.discount) log_quote in
        fun sigma ->
          if E.sign sigma = E.Zero then E.sub intrinsic one
          else
            let s = E.mul c.root_time sigma in
            let d = E.div c.distance s in
            let z =
              match E.sign d with
              | E.Negative -> E.neg d
              | E.Positive | E.Zero -> d
              | E.Indeterminate -> hull d (E.neg d)
            in
            let log_weight = E.add base (E.log s) in
            let otm =
              if E.magnitude z <= 4.0 then
                E.mul (exp log_weight) (E.sub (pdf z) (E.mul z (cdf (E.neg z))))
              else E.mul (gaussian log_weight z) (E.sub one (E.mul z (mills z)))
            in
            E.sub (E.add intrinsic otm) one
