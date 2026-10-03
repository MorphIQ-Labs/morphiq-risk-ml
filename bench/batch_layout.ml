open Morphiq_risk

let ok = function Ok x -> x | Error _ -> failwith "unexpected error"

let measure f =
  Gc.full_major ();
  let before = Gc.quick_stat () and start = Unix.gettimeofday () in
  let values = f () in
  let elapsed = Unix.gettimeofday () -. start and after = Gc.quick_stat () in
  ( values,
    elapsed,
    after.minor_words +. after.major_words -. after.promoted_words
    -. before.minor_words -. before.major_words +. before.promoted_words )

let () =
  let count = ref 256 in
  Arg.parse
    [
      ("--count", Arg.Set_int count, "batch size");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "batch-layout-v1";
            exit 0),
        "version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "batch_layout";
  if !count < 0 then failwith "negative count";
  let inputs =
    Array.init !count (fun i ->
        Black.Black76_carry.
          {
            forward = 100.;
            strike = 95. +. float_of_int (i mod 11);
            time_to_expiry = 1.;
            rate = 0.02;
          })
  in
  let sigma = ok (Vol.lognormal 0.2) in
  let eval i =
    Batch.evaluate
      (Batch.Request
         ( Batch.Black76,
           i,
           Side.Call,
           Batch.Evaluate (sigma, Production.Price, 1e-10) ))
  in
  let scalar, scalar_s, scalar_words =
    measure (fun () ->
        Array.map
          (fun i ->
            match Production.Black76.admit i with
            | Error e -> Error e
            | Ok a ->
                Production.Black76.evaluate a Side.Call sigma Production.Price
                  ~max_error:1e-10)
          inputs)
  in
  let batch, batch_s, batch_words =
    measure (fun () ->
        let requests =
          Array.map
            (fun i ->
              Batch.Request
                ( Batch.Black76,
                  i,
                  Side.Call,
                  Batch.Evaluate (sigma, Production.Price, 1e-10) ))
            inputs
        in
        Batch.run requests)
  in
  let packed, packed_s, packed_words =
    measure (fun () ->
        (* A deliberate SoA alternative includes packing AND scalar-record extraction.
       No alternate unchecked pricing path is used. *)
        let forwards = Array.map (fun i -> i.Black.Black76_carry.forward) inputs
        and strikes = Array.map (fun i -> i.Black.Black76_carry.strike) inputs
        and times =
          Array.map (fun i -> i.Black.Black76_carry.time_to_expiry) inputs
        and rates = Array.map (fun i -> i.Black.Black76_carry.rate) inputs in
        Array.init !count (fun j ->
            eval
              Black.Black76_carry.
                {
                  forward = forwards.(j);
                  strike = strikes.(j);
                  time_to_expiry = times.(j);
                  rate = rates.(j);
                }))
  in
  if scalar <> batch || scalar <> packed || Array.exists Result.is_error scalar
  then failwith "layout conformance";
  Printf.printf
    "{\"count\":%d,\"scalar_s\":%.9g,\"batch_s\":%.9g,\"packed_s\":%.9g,\"scalar_words\":%.17g,\"batch_words\":%.17g,\"packed_words\":%.17g,\"identical\":true}\n"
    !count scalar_s batch_s packed_s scalar_words batch_words packed_words
