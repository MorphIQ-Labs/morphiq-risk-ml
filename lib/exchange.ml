type leg = Receive | Deliver
type field = Spot | Dividend_yield

type input_error =
  | Invalid_asset of leg * field
  | Invalid_time
  | Invalid_correlation

type correlation = float

let correlation x =
  if Float.is_finite x && x >= -1. && x <= 1. then Ok x
  else Error Invalid_correlation

type asset = {
  spot : float;
  dividend_yield : float;
  volatility : Vol.lognormal Vol.t;
}

type admitted = {
  receive : asset;
  deliver : asset;
  time : float;
  rho : correlation;
}

let admit ~receive ~deliver ~time_to_expiry ~correlation =
  let validate leg asset =
    if not (Float.is_finite asset.spot && asset.spot >= 0.) then
      Error (Invalid_asset (leg, Spot))
    else if not (Float.is_finite asset.dividend_yield) then
      Error (Invalid_asset (leg, Dividend_yield))
    else Ok ()
  in
  match (validate Receive receive, validate Deliver deliver) with
  | Error e, _ | _, Error e -> Error e
  | Ok (), Ok () ->
      if not (Float.is_finite time_to_expiry && time_to_expiry >= 0.) then
        Error Invalid_time
      else Ok { receive; deliver; time = time_to_expiry; rho = correlation }

type error = Invalid_accuracy | Numerical_failure | Accuracy_exceeded
type certified_price = { value : float; absolute_error : float }

module E = Enclosure
module M = Model_enclosure

let positive_part x =
  match E.sign x with
  | E.Positive -> x
  | E.Negative | E.Zero -> E.exact 0.
  | E.Indeterminate -> E.add_error (E.exact 0.) (E.magnitude x)

let total_deviation a sigma1 sigma2 =
  (* Normalize before covariance products: original low words and scaling
     uncertainty remain inside the enclosure through sqrt and restoration. *)
  let exponent = snd (Float.frexp (Float.max sigma1 sigma2)) in
  let u1 = E.scale (E.exact sigma1) (-exponent) in
  let u2 = E.scale (E.exact sigma2) (-exponent) in
  let difference = E.sub u1 u2 in
  let cross =
    E.mul (E.mul_float (E.mul u1 u2) 2.) (E.sub (E.exact 1.) (E.exact a.rho))
  in
  let variance = E.add (E.mul difference difference) cross in
  let time_exponent = (snd (Float.frexp a.time) asr 1) * 2 in
  let time = E.scale (E.exact a.time) (-time_exponent) in
  let s =
    E.scale (E.sqrt (E.mul variance time)) (exponent + (time_exponent / 2))
  in
  if E.sign s <> E.Positive then
    raise (E.Unresolved "exchange positive variance unresolved");
  s

let enclose a =
  let s1 = a.receive.spot and s2 = a.deliver.spot in
  let q1 = a.receive.dividend_yield and q2 = a.deliver.dividend_yield in
  let sigma1 = Vol.to_float a.receive.volatility
  and sigma2 = Vol.to_float a.deliver.volatility in
  let zero_variance =
    (sigma1 = 0. && sigma2 = 0.) || (a.rho = 1. && sigma1 = sigma2)
  in
  if a.time = 0. then positive_part (E.sub (E.exact s1) (E.exact s2))
  else if s1 = 0. then E.exact 0.
  else if zero_variance && s1 = s2 && q1 = q2 then E.exact 0.
  else
    let exponent = snd (Float.frexp (Float.max s1 s2)) in
    let normalized x = E.scale (E.exact x) (-exponent) in
    let discount q = E.exp (E.neg (E.mul (E.exact q) (E.exact a.time))) in
    let asset1 = E.mul (normalized s1) (discount q1) in
    let result =
      if s2 = 0. then asset1
      else if zero_variance && q1 = q2 then
        E.mul
          (positive_part (E.sub (normalized s1) (normalized s2)))
          (discount q1)
      else
        let asset2 = E.mul (normalized s2) (discount q2) in
        if zero_variance then positive_part (E.sub asset1 asset2)
        else
          let s = total_deviation a sigma1 sigma2 in
          let log_ratio =
            E.add
              (E.sub (E.log (E.exact s1)) (E.log (E.exact s2)))
              (E.mul (E.sub (E.exact q2) (E.exact q1)) (E.exact a.time))
          in
          let d1 = E.add (E.div log_ratio s) (E.scale s (-1)) in
          let d2 = E.sub d1 s in
          E.sub (E.mul asset1 (M.cdf d1)) (E.mul asset2 (M.cdf d2))
    in
    E.scale result exponent

let price admitted ~max_error =
  if not (Float.is_finite max_error && max_error >= 0.) then
    Error Invalid_accuracy
  else
    try
      let enclosed = enclose admitted in
      let value = Float.max 0. enclosed.hi in
      let absolute_error = E.error_of_float enclosed value in
      if
        not
          (Float.is_finite value
          && Float.is_finite absolute_error
          && absolute_error >= 0.)
      then Error Numerical_failure
      else if absolute_error > max_error then Error Accuracy_exceeded
      else Ok { value; absolute_error }
    with E.Unresolved _ -> Error Numerical_failure
