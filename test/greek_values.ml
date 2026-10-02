open Morphiq_risk

let get = function Ok v -> v | Error e -> failwith (Refusal.to_string e)

let rate =
  Result.map (fun v -> (v : Units.per_calendar_day Units.time_rate :> float))

let volatility_rate r =
  Result.map
    (fun v ->
      (v : (Units.per_calendar_day, _) Units.volatility_time_rate :> float))
    r

let per_vol r = Result.map (fun v -> (v : _ Units.per_volatility :> float)) r

let per_vol2 r =
  Result.map (fun v -> (v : _ Units.per_volatility_squared :> float)) r

let pick (g : _ Greeks.t) = function
  | "delta" -> g.delta
  | "gamma" -> g.gamma
  | "theta" -> rate g.theta
  | "vega" -> per_vol g.vega
  | "rho" -> g.rho
  | "vanna" -> per_vol g.vanna
  | "volga" -> per_vol2 g.volga
  | "charm" -> rate g.charm
  | "veta" -> volatility_rate g.veta
  | "color" -> rate g.color
  | n -> invalid_arg n

let greeks model side ~s ~k ~t ~r ~q ~sigma ~shift =
  match model with
  | "bsm" ->
      let a =
        get
          (Black.Bsm.admit
             {
               spot = s;
               strike = k;
               time_to_expiry = t;
               rate = r;
               dividend_yield = q;
             })
      in
      `Black (Black.Bsm.greeks a side (get (Vol.lognormal sigma)))
  | "black76" ->
      let a =
        get
          (Black.Black76.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      `Black (Black.Black76.greeks a side (get (Vol.lognormal sigma)))
  | "displaced" ->
      let a =
        get
          (Black.Displaced.admit
             {
               forward = s;
               strike = k;
               displacement = shift;
               time_to_expiry = t;
               rate = r;
             })
      in
      `Black (Black.Displaced.greeks a side (get (Vol.lognormal sigma)))
  | "bachelier" ->
      let a =
        get
          (Bachelier.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      `Normal (Bachelier.greeks a side (get (Vol.normal sigma)))
  | m -> invalid_arg m

(* The library's price, for rho = -T V in the forward models. *)
let price model side ~s ~k ~t ~r ~sigma ~shift =
  match model with
  | "black76" ->
      let a =
        get
          (Black.Black76.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Black.Black76.price a side (get (Vol.lognormal sigma))
  | "displaced" ->
      let a =
        get
          (Black.Displaced.admit
             {
               forward = s;
               strike = k;
               displacement = shift;
               time_to_expiry = t;
               rate = r;
             })
      in
      Black.Displaced.price a side (get (Vol.lognormal sigma))
  | "bachelier" ->
      let a =
        get
          (Bachelier.admit
             { forward = s; strike = k; time_to_expiry = t; rate = r })
      in
      Bachelier.price a side (get (Vol.normal sigma))
  | m -> invalid_arg m

let forward_rho model greek =
  greek = "rho" && List.mem model [ "black76"; "displaced"; "bachelier" ]
