type why = Payoff_kink
type 'a value = ('a, why) result

type 'coordinate t = {
  delta : float value;
  gamma : float value;
  theta : Units.per_calendar_day Units.time_rate value;
  vega : 'coordinate Units.per_volatility value;
  rho : float value;
  vanna : 'coordinate Units.per_volatility value;
  volga : 'coordinate Units.per_volatility_squared value;
  charm : Units.per_calendar_day Units.time_rate value;
  veta : Units.per_calendar_day Units.time_rate value;
  color : Units.per_calendar_day Units.time_rate value;
}

let kink = Error Payoff_kink
let daily annual = Ok (Units.per_calendar_day annual)

(* The payoff max(θ(S - K), 0) at expiry: off strike every derivative is the
   payoff's own (slope θ or 0), and the time Greeks are right limits in
   remaining maturity (FerroRisk SPEC §8.1). At the strike the payoff has a
   kink, and the spot and time derivatives do not exist. *)
let expiry ~theta ~spot ~strike ~rate ~yield =
  let zero = Ok 0.0 in
  if spot = strike then
    {
      delta = kink;
      gamma = kink;
      theta = kink;
      vega = Ok (Units.per_volatility 0.0);
      rho = zero;
      vanna = kink;
      volga = Ok (Units.per_volatility_squared 0.0);
      charm = kink;
      veta = kink;
      color = kink;
    }
  else
    let itm = theta *. (spot -. strike) > 0.0 in
    {
      delta = Ok (if itm then theta else 0.0);
      gamma = zero;
      (* q S - r K cancels when S is near K; both products are exact
         double-doubles, so the difference is rounded once. *)
      theta = daily (if itm then theta *. Dd.to_float (Dd.sub (Dd.two_prod yield spot) (Dd.two_prod rate strike)) else 0.0);
      vega = Ok (Units.per_volatility 0.0);
      rho = zero;
      vanna = Ok (Units.per_volatility 0.0);
      volga = Ok (Units.per_volatility_squared 0.0);
      charm = daily (if itm then theta *. yield else 0.0);
      veta = daily 0.0;
      color = daily 0.0;
    }
