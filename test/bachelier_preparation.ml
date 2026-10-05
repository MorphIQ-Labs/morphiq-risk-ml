open Morphiq_risk
module P = Internal.Bachelier_fast

let get = function Ok x -> x | Error _ -> failwith "admission"
let check yes why = if not yes then failwith why
let same x y = Int64.bits_of_float x = Int64.bits_of_float y

let () =
  let rows = Fast_reference_cases.load Sys.argv in
  let count = ref 0 in
  Array.iter
    (fun (Batch.Fast.Price (model, inputs, side, vol), _) ->
      match model with
      | Batch.Bachelier -> (
          match Bachelier.admit inputs with
          | Error _ -> ()
          | Ok a -> (
              match P.prepare a side vol with
              | None -> ()
              | Some prepared ->
                  incr count;
                  check
                    (same (P.price prepared) (Bachelier.price a side vol))
                    "prepared oracle-row replay"))
      | _ -> ())
    rows;
  check (!count > 0) "empty selected coverage";
  let request q side time sigma =
    let inputs : Bachelier.inputs =
      {
        forward = -.Side.sign side *. q;
        strike = 0.;
        time_to_expiry = time;
        rate = 0.;
      }
    in
    let a = get (Bachelier.admit inputs) and v = get (Vol.normal sigma) in
    (a, v, P.prepare a side v)
  in
  List.iter
    (fun side ->
      List.iter
        (fun q ->
          let a, v, prepared = request q side 1. 1. in
          let p =
            match prepared with
            | Some p -> p
            | None -> failwith "eligible boundary"
          in
          check (same (P.price p) (Bachelier.price a side v)) "boundary replay";
          let worker = Domain.spawn (fun () -> P.price p) in
          check
            (same (P.price p) (Domain.join worker))
            "concurrent immutable preparation")
        [ 0.46875; 1.; 4. ];
      List.iter
        (fun (q, time, sigma) ->
          let _, _, prepared = request q side time sigma in
          check (Option.is_none prepared) "fallback boundary")
        [
          (0., 1., 1.);
          (-1., 1., 1.);
          (0.25, 1., 1.);
          (5., 1., 1.);
          (1., 0., 1.);
          (1., 1., 0.);
          (0x1p101, 1., 1.);
        ])
    [ Side.Call; Side.Put ];
  Printf.printf
    "Bachelier preparation: %d fixture selections, boundaries and concurrent \
     replay pass\n"
    !count
