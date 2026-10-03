open Morphiq_risk

let count = ref 0
let require message yes = if not yes then failwith message
let value = function Ok x -> x | Error _ -> failwith "unexpected refusal"

let check model side ~s ~t ~r ~shift expected =
  let inspect g =
    require "theta is exactly zero" (value (Greek_values.pick g "theta") = 0.0);
    if model = "bsm" then
      require "BSM rho retains its kink"
        (g.Greeks.rho = Error Greeks.Payoff_kink)
    else require "forward rho is exactly zero" (value g.rho = 0.0);
    List.iter
      (fun name ->
        require
          (name ^ " retains its kink")
          (Greek_values.pick g name = Error Greeks.Payoff_kink))
      [ "delta"; "gamma"; "vanna"; "charm"; "color" ];
    require "volga is zero" (value (Greek_values.pick g "volga") = 0.0);
    let got = value (Greek_values.pick g "veta") in
    require
      (Printf.sprintf "%s S=%h T=%h r=%h shift=%h: veta %h expected %h" model s
         t r shift got expected)
      (got = expected)
  in
  (match
     Greek_values.greeks model side ~s ~k:s ~t ~r ~q:r ~sigma:0.0 ~shift
   with
  | `Black g -> inspect g
  | `Normal g -> inspect g);
  incr count

let () =
  In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line "%s %s %Lx %Lx %Lx %Lx %Lx"
             (fun model side s t r shift reference ->
               let f = Int64.float_of_bits in
               check model
                 (if side = "call" then Side.Call else Side.Put)
                 ~s:(f s) ~t:(f t) ~r:(f r) ~shift:(f shift) (f reference)));
  (* Changing r or T leaves the forward ATM zero-variance payoff identically
     zero. This tests the varied-coordinate identity, not a difference quotient. *)
  List.iter
    (fun model ->
      List.iter
        (fun side ->
          List.iter
            (fun r ->
              List.iter
                (fun t ->
                  require "ATM forward value under rate/time changes"
                    (Greek_values.price model side ~s:1. ~k:1. ~t ~r ~sigma:0.
                       ~shift:0.125
                    = 0.))
                [ 0.125; 0.7; 1.; 4.; 16. ])
            [ -0.5; -0.01; 0.; 0.01; 0.5 ])
        [ Side.Call; Side.Put ])
    [ "black76"; "displaced"; "bachelier" ];
  (* Adjacent off-ATM contracts have zero right vega/veta; their spot/rate
     derivatives exist. They must not be classified from rounded price zero. *)
  List.iter
    (fun model ->
      List.iter
        (fun side ->
          List.iter
            (fun s ->
              let inspect g =
                List.iter
                  (fun name ->
                    require
                      ("off-ATM " ^ name ^ " is zero")
                      (value (Greek_values.pick g name) = 0.))
                  [ "vega"; "veta"; "gamma"; "volga" ];
                ignore (value g.Greeks.rho);
                ignore (value g.delta)
              in
              match
                Greek_values.greeks model side ~s ~k:1. ~t:1. ~r:0. ~q:0.
                  ~sigma:0. ~shift:0.125
              with
              | `Black g -> inspect g
              | `Normal g -> inspect g)
            [ Float.pred 1.; Float.succ 1. ])
        [ Side.Call; Side.Put ])
    [ "bsm"; "black76"; "displaced"; "bachelier" ];
  (* This finite mathematical input exceeds the bounded exponential capability.
     The derivative exists; reporting Payoff_kink would be a false statement. *)
  List.iter
    (fun model ->
      let inspect g =
        require "unresolved veta is a numerical failure"
          (g.Greeks.veta = Error Greeks.Numerical_failure)
      in
      match
        Greek_values.greeks model Side.Call ~s:1. ~k:1. ~t:1. ~r:(-2000.)
          ~q:(-2000.) ~sigma:0. ~shift:0.125
      with
      | `Black g -> inspect g
      | `Normal g -> inspect g)
    [ "bsm"; "black76"; "displaced"; "bachelier" ];
  Printf.printf
    "%d nearest-even boundary veta references; exact-zero, kink, adjacent and \
     numerical-failure controls pass\n"
    !count;
  require "empty fixture" (!count > 0)
