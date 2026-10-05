open Morphiq_risk
module P = Internal.Bachelier_fast
module N = Internal.Bachelier_native

let get = function Ok x -> x | Error _ -> failwith "reference volatility"

let () =
  let paths = ref [] and external_reference = ref false in
  Arg.parse
    [
      ( "--external-reference",
        Arg.Set external_reference,
        "Read separately retained experiment inputs" );
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "native-bachelier-reference-1";
            exit 0),
        "Version" );
    ]
    (fun path -> paths := path :: !paths)
    "native_bachelier_reference [--external-reference] FILE...";
  let cases = ref [] and total = ref 0 in
  List.iter
    (fun path ->
      Oracle_fixture.lines ~external_reference:!external_reference
        ~columns:[ 12 ]
        ~names:[ "european"; "displaced" ]
        path
      |> List.iter (fun line ->
             incr total;
             Scanf.sscanf line "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
               (fun
                 model side _region _family f k t r _q sigma _shift reference ->
                 if model = "bachelier" then
                   let f, k, t, r, sigma, reference =
                     ( Int64.float_of_bits f,
                       Int64.float_of_bits k,
                       Int64.float_of_bits t,
                       Int64.float_of_bits r,
                       Int64.float_of_bits sigma,
                       Int64.float_of_bits reference )
                   in
                   let side =
                     match side with
                     | "call" -> Side.Call
                     | "put" -> Side.Put
                     | _ -> failwith "side"
                   in
                   let vol = get (Vol.normal sigma) in
                   match
                     Bachelier.admit
                       { forward = f; strike = k; time_to_expiry = t; rate = r }
                   with
                   | Error _ -> ()
                   | Ok a -> (
                       match P.prepare a side vol with
                       | None -> ()
                       | Some p ->
                           let scale =
                             Float.exp (-.r *. t)
                             *. (Float.max (Float.abs f) (Float.abs k)
                                +. sigma *. Float.sqrt t
                                   /. Float.sqrt (2. *. Float.pi))
                           in
                           cases :=
                             ( p,
                               reference,
                               scale,
                               Bachelier.price a side vol,
                               Batch.Fast.Price
                                 ( Batch.Bachelier,
                                   {
                                     forward = f;
                                     strike = k;
                                     time_to_expiry = t;
                                     rate = r;
                                   },
                                   side,
                                   vol ),
                               line )
                             :: !cases))))
    (List.rev !paths);
  let cases = Array.of_list (List.rev !cases) in
  if Array.length cases = 0 then failwith "empty native reference coverage";
  let plan = N.compile (Array.map (fun (p, _, _, _, _, _) -> p) cases) in
  let check output =
    Array.iteri
      (fun i got ->
        let _, reference, scale, baseline, _, line = cases.(i) in
        let norm = Float.abs (got -. reference) /. (Float.epsilon *. scale) in
        (* Check independent accuracy before replay, including in mutation runs. *)
        if
          not
            (Float_score.within ~budget:8. got reference
            && Float.is_finite norm && norm <= 4.3)
        then
          failwith
            (Printf.sprintf "native independent reference failure at %d: %s" i
               line);
        Certified.require_replay
          (Int64.bits_of_float got = Int64.bits_of_float baseline)
          (Printf.sprintf "native bit compatibility failure at %d" i))
      output
  in
  List.iter (fun scalar -> check (N.execute ~scalar plan)) [ true; false ];
  let public =
    Batch.Fast.compile
      (Array.map (fun (_, _, _, _, request, _) -> request) cases)
  in
  check
    (Array.map
       (function
         | Ok v -> v | Error _ -> failwith "public selected batch failure")
       (Batch.Fast.execute public));
  Printf.printf
    "Native Bachelier: %d selected of %d input rows; independent \
     8-ULP/4.3-epsilon gates and exact replay pass\n"
    (Array.length cases) !total
