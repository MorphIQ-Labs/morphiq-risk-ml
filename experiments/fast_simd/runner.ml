open Morphiq_risk
module F = Batch.Fast
module I = Internal

external kernel : int -> float array -> float array -> unit
  = "morphiq_simd_kernel"

external clock : unit -> float = "morphiq_simd_clock"

let ok = function Ok x -> x | Error _ -> failwith "invalid experiment input"
let normal x = ok (Vol.normal x)
let lognormal x = ok (Vol.lognormal x)
let range x = Float.is_finite x && x >= 0x1p-100 && x <= 0x1p100

let prepare (F.Price (model, inputs, side, vol)) =
  match model with
  | Batch.Bachelier -> (
      match Bachelier.admit inputs with
      | Error _ -> None
      | Ok _ ->
          let theta = Side.sign side in
          let distance, low =
            I.Split.two_sum inputs.forward (-.inputs.strike)
          in
          let root, root_low = I.Split.sqrt inputs.time_to_expiry in
          let s =
            I.Dd.mul_float { hi = root; lo = root_low } (Vol.to_float vol)
          in
          let product = inputs.rate *. inputs.time_to_expiry in
          let residual =
            Float.fma inputs.rate inputs.time_to_expiry (-.product)
          in
          let discount =
            if product >= 0. then I.Split.scaled_exp_neg 1. product residual
            else I.Elementary.exp (-.product) *. (1. -. residual)
          in
          if
            inputs.time_to_expiry <= 0.
            || Vol.to_float vol <= 0.
            || theta *. distance > 0.
            || (not (range (Float.abs distance)))
            || not (range s.hi && range discount)
          then None
          else
            let a, al =
              if distance < 0. then (-.distance, -.low) else (distance, low)
            in
            let q, r = I.Split.quotient_dd a al s.hi s.lo in
            let d = q +. r in
            if Float.is_finite q && Float.is_finite r && d >= 0.46875 && d <= 4.
            then Some (q, r, s.hi, discount)
            else None)
  | _ -> None

type plan = {
  length : int;
  indices : int array;
  parameters : float array;
  padded : int;
  fallback_indices : int array;
  fallback : F.t;
}

let compile requests =
  let selected = ref [] and fallback = ref [] in
  Array.iteri
    (fun index request ->
      match prepare request with
      | Some p -> selected := (index, p) :: !selected
      | None -> fallback := (index, request) :: !fallback)
    requests;
  let selected = Array.of_list (List.rev !selected) in
  let fallback = Array.of_list (List.rev !fallback) in
  let count = Array.length selected in
  let padded = count + (count mod 2) in
  let parameters = Array.make (4 * padded) 1. in
  Array.iteri
    (fun i (_, (q, r, s, discount)) ->
      parameters.(i) <- q;
      parameters.(padded + i) <- r;
      parameters.((2 * padded) + i) <- s;
      parameters.((3 * padded) + i) <- discount)
    selected;
  if count < padded then parameters.(padded + count) <- 0.;
  {
    length = Array.length requests;
    indices = Array.map fst selected;
    parameters;
    padded;
    fallback_indices = Array.map fst fallback;
    fallback = F.compile (Array.map snd fallback);
  }

let ocaml_kernel p out =
  for i = 0 to p.padded - 1 do
    let q = p.parameters.(i) and r = p.parameters.(p.padded + i) in
    let s = p.parameters.((2 * p.padded) + i) in
    let discount = p.parameters.((3 * p.padded) + i) in
    let square, low = I.Split.square q in
    let m =
      discount *. s *. 0.39894228040143267794
      *. I.Normalised_black.y_prime (-.(q +. r))
    in
    out.(i) <-
      I.Split.scaled_exp_neg m (0.5 *. square) ((0.5 *. low) +. (q *. r))
  done

let checked x =
  if Float.is_finite x && x >= 0. then Ok x else Error F.Numerical_failure

let execute mode p =
  let output = Array.make p.padded 0. in
  if mode = 0 then ocaml_kernel p output else kernel mode p.parameters output;
  let results = Array.make p.length (Error F.Numerical_failure) in
  Array.iteri (fun i index -> results.(index) <- checked output.(i)) p.indices;
  let other = F.execute p.fallback in
  Array.iteri (fun i index -> results.(index) <- other.(i)) p.fallback_indices;
  results

let signature = function
  | Ok x -> Printf.sprintf "%016Lx" (Int64.bits_of_float x)
  | Error F.Numerical_failure -> "numerical_failure"
  | Error (F.Invalid_input e) -> "invalid:" ^ Refusal.to_string e

let equal a b = Array.map signature a = Array.map signature b

let modes =
  [|
    "batch-fast"; "prepared-ocaml"; "native-scalar"; "native-simd"; "sleef-simd";
  |]

let request family i =
  let side = if i mod 2 = 0 then Side.Call else Side.Put in
  let q = 0.5 +. (float (i mod 43) *. (3.4 /. 42.)) in
  let sigma = 0.75 +. (float (i mod 17) /. 8.) in
  let t = 0.25 +. (float (i mod 11) /. 4.) in
  let rate = -0.02 +. (float (i mod 7) /. 100.) in
  let make q side =
    let k = 10. +. float (i mod 5) in
    let f = k -. (Side.sign side *. q *. sigma *. Float.sqrt t) in
    F.Price
      ( Batch.Bachelier,
        { forward = f; strike = k; time_to_expiry = t; rate },
        side,
        normal sigma )
  in
  if family = "eligible" then make q side
  else if family = "fallback-heavy" then
    if i mod 4 = 3 then make q side else make 0.2 side
  else if family = "mixed" then
    match i mod 4 with
    | 0 -> make q side
    | 1 ->
        F.Price
          ( Batch.Bsm,
            {
              spot = 100.;
              strike = 95.;
              time_to_expiry = t;
              rate;
              dividend_yield = 0.01;
            },
            side,
            lognormal 0.2 )
    | 2 ->
        F.Price
          ( Batch.Black76,
            { forward = 100.; strike = 95.; time_to_expiry = t; rate },
            side,
            lognormal 0.2 )
    | _ ->
        F.Price
          ( Batch.Displaced,
            {
              forward = -2.;
              strike = -1.;
              displacement = 5.;
              time_to_expiry = t;
              rate;
            },
            side,
            lognormal 0.2 )
  else invalid_arg "family"

let words () =
  let a, b, c = Gc.counters () in
  a +. c -. b

let sink x = ignore (Sys.opaque_identity x)

let bench family n reverse =
  let requests = Array.init n (request family) in
  let base = F.compile requests and p = compile requests in
  let expected = F.execute base in
  for mode = 0 to 2 do
    if not (equal expected (execute mode p)) then
      failwith "benchmark exact replay"
  done;
  let names =
    if reverse then Array.init 5 (fun i -> 4 - i) else Array.init 5 Fun.id
  in
  Array.iter
    (fun backend ->
      let cases =
        if backend = 0 then
          [
            ("compile", fun () -> sink (F.compile requests));
            ("execute", fun () -> sink (F.execute base));
            ("one-shot", fun () -> sink (F.run requests));
          ]
        else
          [
            ("compile", fun () -> sink (compile requests));
            ("execute", fun () -> sink (execute (backend - 1) p));
            ( "one-shot",
              fun () -> sink (execute (backend - 1) (compile requests)) );
          ]
      in
      List.iter
        (fun (phase, f) ->
          for _ = 1 to 3 do
            f ()
          done;
          let iterations = max 2 (8192 / max 1 n) in
          for sample = 1 to 5 do
            Gc.full_major ();
            let before = words () and cpu = Sys.time () and start = clock () in
            for _ = 1 to iterations do
              f ()
            done;
            let elapsed = clock () -. start in
            let cpu = Sys.time () -. cpu
            and bytes = 8. *. (words () -. before) in
            Printf.printf
              "{\"kind\":\"timing\",\"family\":%S,\"n\":%d,\"eligible\":%d,\"backend\":%S,\"phase\":%S,\"sample\":%d,\"iterations\":%d,\"ns\":%.9g,\"cpu_ns\":%.9g,\"bytes\":%.9g}\n\
               %!"
              family n (Array.length p.indices) modes.(backend) phase sample
              iterations
              (elapsed *. 1e9 /. float iterations)
              (cpu *. 1e9 /. float iterations)
              (bytes /. float iterations)
          done)
        cases)
    names

let parse line =
  Scanf.sscanf line "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
    (fun model side _region _family s k t r q sigma shift _reference ->
      let f = Int64.float_of_bits in
      let s = f s
      and k = f k
      and t = f t
      and r = f r
      and q = f q
      and sigma = f sigma
      and shift = f shift in
      let side =
        if side = "call" then Side.Call
        else if side = "put" then Side.Put
        else invalid_arg "side"
      in
      match model with
      | "bsm" ->
          F.Price
            ( Batch.Bsm,
              {
                spot = s;
                strike = k;
                time_to_expiry = t;
                rate = r;
                dividend_yield = q;
              },
              side,
              lognormal sigma )
      | "black76" ->
          F.Price
            ( Batch.Black76,
              { forward = s; strike = k; time_to_expiry = t; rate = r },
              side,
              lognormal sigma )
      | "displaced" ->
          F.Price
            ( Batch.Displaced,
              {
                forward = s;
                strike = k;
                displacement = shift;
                time_to_expiry = t;
                rate = r;
              },
              side,
              lognormal sigma )
      | "bachelier" ->
          F.Price
            ( Batch.Bachelier,
              { forward = s; strike = k; time_to_expiry = t; rate = r },
              side,
              normal sigma )
      | _ -> invalid_arg "model")

let validate path =
  let ic = open_in path in
  let rec read acc =
    match input_line ic with
    | line when line = "" || line.[0] = '#' -> read acc
    | line -> read (line :: acc)
    | exception End_of_file ->
        close_in ic;
        Array.of_list (List.rev acc)
  in
  let lines = read [] in
  let requests = Array.map parse lines in
  let p = compile requests in
  let selected = Array.make (Array.length requests) false in
  Array.iter (fun i -> selected.(i) <- true) p.indices;
  let results =
    Array.init 5 (fun i -> if i = 0 then F.run requests else execute (i - 1) p)
  in
  Array.iteri
    (fun i _ ->
      Printf.printf "{\"row\":%d,\"eligible\":%b,\"outcomes\":[%s]}\n" i
        selected.(i)
        (String.concat ","
           (Array.to_list
              (Array.map
                 (fun a -> Printf.sprintf "%S" (signature a.(i)))
                 results))))
    requests;
  flush stdout

let controls () =
  List.iter
    (fun n ->
      let a = Array.init n (request "mixed") in
      let p = compile a in
      let expected = F.run a in
      if n > 0 then a.(0) <- request "eligible" 7;
      for mode = 0 to 2 do
        let got = execute mode p in
        if not (equal expected got) then failwith "freeze/order/control";
        if n > 0 then got.(0) <- Ok 123.;
        if not (equal expected (execute mode p)) then failwith "output alias"
      done;
      let d = Domain.spawn (fun () -> execute 2 p) in
      let direct = execute 2 p in
      if not (equal direct (Domain.join d)) then failwith "concurrent replay")
    [ 0; 1; 2; 3; 17; 256 ];
  let rejects f =
    match f () with
    | () -> failwith "negative control accepted"
    | exception Invalid_argument _ -> ()
  in
  rejects (fun () -> kernel 9 [||] [||]);
  rejects (fun () -> kernel 1 [| 1. |] [| 1.; 1. |]);
  rejects (fun () -> kernel 1 (Array.make 4 0.) [| 0. |]);
  print_endline "CONTROLS PASS"

let dump_inputs () =
  List.iter
    (fun family ->
      for i = 0 to 4095 do
        let (F.Price (model, inputs, side, vol)) = request family i in
        let name, s, k, t, r, q, shift =
          match model with
          | Batch.Bsm ->
              ( "bsm",
                inputs.spot,
                inputs.strike,
                inputs.time_to_expiry,
                inputs.rate,
                inputs.dividend_yield,
                0. )
          | Batch.Black76 ->
              ( "black76",
                inputs.forward,
                inputs.strike,
                inputs.time_to_expiry,
                inputs.rate,
                0.,
                0. )
          | Batch.Displaced ->
              ( "displaced",
                inputs.forward,
                inputs.strike,
                inputs.time_to_expiry,
                inputs.rate,
                0.,
                inputs.displacement )
          | Batch.Bachelier ->
              ( "bachelier",
                inputs.forward,
                inputs.strike,
                inputs.time_to_expiry,
                inputs.rate,
                0.,
                0. )
        in
        Printf.printf "%s %s benchmark %s %s 0000000000000000\n" name
          (if side = Side.Call then "call" else "put")
          ("timed-" ^ family)
          (String.concat " "
             (List.map
                (fun x -> Printf.sprintf "%016Lx" (Int64.bits_of_float x))
                [ s; k; t; r; q; Vol.to_float vol; shift ]))
      done)
    [ "eligible"; "fallback-heavy"; "mixed" ]

let () =
  let command = ref ""
  and path = ref ""
  and family = ref "eligible"
  and backend = ref 0
  and reverse = ref false in
  Arg.parse
    [
      ( "--validate",
        Arg.String
          (fun s ->
            command := "validate";
            path := s),
        "Input oracle-format file" );
      ("--bench", Arg.Unit (fun () -> command := "bench"), "Run timed campaign");
      ( "--dump-inputs",
        Arg.Unit (fun () -> command := "dump"),
        "Emit exact benchmark requests" );
      ( "--controls",
        Arg.Unit (fun () -> command := "controls"),
        "Exercise wrapper controls" );
      ( "--profile",
        Arg.Unit (fun () -> command := "profile"),
        "Run one backend for 8 seconds for CPU sampling" );
      ("--backend", Arg.Set_int backend, "Profile backend 0..4");
      ("--family", Arg.Set_string family, "eligible, fallback-heavy, mixed");
      ("--reverse", Arg.Set reverse, "Reverse timing order");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "fast-simd-experiment-v1";
            exit 0),
        "Version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "Optional SIMD experiment";
  match !command with
  | "dump" -> dump_inputs ()
  | "controls" -> controls ()
  | "validate" -> validate !path
  | "bench" ->
      List.iter
        (fun f -> List.iter (fun n -> bench f n !reverse) [ 1; 32; 256; 4096 ])
        [ "eligible"; "fallback-heavy"; "mixed" ]
  | "profile" ->
      if !backend < 0 || !backend > 4 then invalid_arg "backend";
      let requests = Array.init 256 (request !family) in
      let base = F.compile requests and p = compile requests in
      let f =
        if !backend = 0 then fun () -> sink (F.execute base)
        else fun () -> sink (execute (!backend - 1) p)
      in
      let stop = clock () +. 8. in
      let calls = ref 0 in
      while clock () < stop do
        f ();
        incr calls
      done;
      Printf.printf "PROFILE %s %s batches=%d\n" !family modes.(!backend) !calls
  | _ -> invalid_arg "select --controls, --validate, --bench or --profile"
