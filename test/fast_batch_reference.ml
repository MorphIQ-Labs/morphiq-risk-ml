open Morphiq_risk
module F = Batch.Fast

let get = function Ok x -> x | Error _ -> failwith "fixture volatility"

let outcome = function
  | Error e -> Error (F.Invalid_input e)
  | Ok x when Float.is_finite x && x >= 0. -> Ok x
  | Ok _ -> Error F.Numerical_failure

let black (type i) model (module M : Black.MODEL with type inputs = i)
    (inputs : i) side sigma =
  ( F.Price (model, inputs, side, sigma),
    outcome (Result.map (fun a -> M.price a side sigma) (M.admit inputs)) )

let () =
  let rows = ref [] in
  Array.iteri
    (fun index path ->
      if index > 0 then
        Oracle_fixture.lines ~columns:[ 11; 12 ]
          ~names:[ "european"; "displaced" ]
          path
        |> List.iter (fun line ->
               if line <> "" && line.[0] <> '#' then
                 let fields =
                   String.split_on_char ' ' line |> List.filter (( <> ) "")
                 in
                 let fields =
                   match fields with
                   | m :: sd :: rg :: _family :: rest
                     when List.length fields = 12 ->
                       m :: sd :: rg :: rest
                   | xs -> xs
                 in
                 Scanf.sscanf (String.concat " " fields)
                   "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
                   (fun model side _region s k t r q sigma shift _reference ->
                     let f = Int64.float_of_bits in
                     let s, k, t, r, q, sigma, shift =
                       (f s, f k, f t, f r, f q, f sigma, f shift)
                     in
                     let side =
                       match side with
                       | "call" -> Side.Call
                       | "put" -> Side.Put
                       | _ -> failwith "side"
                     in
                     let v = get (Vol.lognormal sigma) in
                     let pair =
                       match model with
                       | "bsm" ->
                           black Batch.Bsm
                             (module Black.Bsm)
                             {
                               spot = s;
                               strike = k;
                               time_to_expiry = t;
                               rate = r;
                               dividend_yield = q;
                             }
                             side v
                       | "black76" | "black76_shifted" ->
                           let s, k =
                             if model = "black76_shifted" then
                               (s +. shift, k +. shift)
                             else (s, k)
                           in
                           black Batch.Black76
                             (module Black.Black76)
                             {
                               forward = s;
                               strike = k;
                               time_to_expiry = t;
                               rate = r;
                             }
                             side v
                       | "displaced" ->
                           black Batch.Displaced
                             (module Black.Displaced)
                             {
                               forward = s;
                               strike = k;
                               displacement = shift;
                               time_to_expiry = t;
                               rate = r;
                             }
                             side v
                       | "bachelier" ->
                           let inputs : Bachelier.inputs =
                             {
                               forward = s;
                               strike = k;
                               time_to_expiry = t;
                               rate = r;
                             }
                           in
                           let v = get (Vol.normal sigma) in
                           ( F.Price (Batch.Bachelier, inputs, side, v),
                             outcome
                               (Result.map
                                  (fun a -> Bachelier.price a side v)
                                  (Bachelier.admit inputs)) )
                       | _ -> failwith "unknown model"
                     in
                     rows := pair :: !rows)))
    Sys.argv;
  let rows = Array.of_list (List.rev !rows) in
  if Array.length rows = 0 then failwith "empty fixture coverage";
  let inputs = Array.map fst rows and expected = Array.map snd rows in
  let check results =
    if Array.length results <> Array.length expected then
      failwith "missing result";
    Array.iteri
      (fun i got ->
        if Marshal.to_string got [] <> Marshal.to_string expected.(i) [] then
          failwith (Printf.sprintf "fast batch scalar mismatch at row %d" i))
      results
  in
  check (F.run inputs);
  check (F.execute (F.compile inputs));
  Printf.printf
    "%d fast batch price outcomes equal scalar words/classes; independent \
     scalar oracle runs separately\n"
    (Array.length rows)
