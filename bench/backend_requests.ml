open Morphiq_risk
module I = Backend_inputs
module A = Early_exercise.Bsm
module B = Batch.American
module P = Planner.American

external clock : unit -> float = "morphiq_bench_monotonic"

let get = I.get

let values (B.Outcome (op, result)) =
  match (op, result) with
  | _, Error _ -> []
  | B.Price _, Ok p ->
      [ p.value; p.maximum_residual; p.maximum_roundoff_indicator ]
  | B.Certified_price _, Ok p -> [ p.value; p.absolute_error ]
  | B.Implied _, Ok p -> [ p.lower.price.value; p.upper.price.value ]
  | B.Greeks _, Ok p ->
      p.price.value
      :: List.filter_map
           (function _, A.Greek_estimate g -> Some g.value | _ -> None)
           p.greeks

let main () =
  let case = ref "flat"
  and size = ref 1
  and reverse = ref false
  and capture = ref false in
  Arg.parse
    [
      ( "--",
        Arg.Rest (fun _ -> raise (Arg.Bad "unexpected positional argument")),
        "end options" );
      ("--case", Arg.Set_string case, "workload");
      ("--size", Arg.Set_int size, "1 or 4");
      ("--reverse", Arg.Set reverse, "reverse methods");
      ("--capture", Arg.Set capture, "one scalar request only");
      ( "--version",
        Arg.Unit
          (fun () ->
            print_endline "american-backend-requests 1";
            exit 0),
        "version" );
    ]
    (fun _ -> raise (Arg.Bad "unexpected argument"))
    "American backend requests";
  if (not (List.mem !case I.cases)) || not (List.mem !size [ 1; 4 ]) then
    invalid_arg "case or size";
  let items = Array.init !size (I.make_item !case) in
  let points =
    if !size = 1 then [| (0, 100.) |] else [| (0, 100.); (30, 101.) |]
  in
  let n = !size * Array.length points in
  let requests () =
    Array.init n (fun i ->
        let offset, spot = points.(i / !size) in
        let (B.Request r) = items.(i mod !size).request ~offset ~spot in
        B.Request { r with id = string_of_int i })
  in
  let admitted = requests () in
  let scalar () = Array.map I.scalar admitted in
  let emit rows =
    Array.iteri
      (fun i (r : B.row) ->
        Printf.printf "ROW\t%d\t%s\t%s\n%!" i (I.digest r)
          (String.concat ","
             (List.concat_map (fun o -> I.status (I.convert o)) r.outcomes));
        Printf.printf "VALUES\t%d\t%s\n%!" i
          (String.concat ","
             (List.map (Printf.sprintf "%h")
                (List.concat_map values r.outcomes))))
      rows
  in
  if !capture then emit (scalar ())
  else
    let batch_compile () =
      get
        (B.compile
           ~limits:
             {
               max_requests = n;
               max_outputs = n;
               max_solver_workspace_bytes = 8388608;
             }
           admitted)
    in
    let batch = batch_compile () in
    let scenarios =
      get
        (Scenario.paired
           (Array.map
              (fun (offset_days, spot) ->
                Scenario.
                  {
                    offset_days;
                    shocks =
                      [
                        {
                          factor = "S";
                          field = Spot;
                          adjustment = Replace spot;
                        };
                      ];
                  })
              points))
    in
    let plan_compile () =
      get
        (P.compile ~snapshot_id:"backend-comparison-v1" ~base_day:0
           ~day_count:Planner.Actual_365_fixed
           ~cash_at_valuation:P.Before_payment
           ~portfolio:(Array.map (fun i -> i.I.position) items)
           ~market:P.[| { name = "S"; spot = 100. } |]
           ~scenarios
           ~limits:
             P.
               {
                 max_instruments = !size;
                 max_market_factors = 1;
                 max_scenarios = Array.length points;
                 max_calculations = n;
                 tile_rows = 1;
                 max_workers = 4;
                 max_buffered_results = 4;
                 max_solver_workspace_bytes = 8388608;
                 max_schedule_events = 16;
               })
    in
    let plan = plan_compile () in
    let reference = scalar () in
    emit reference;
    if I.payload reference <> I.payload (B.execute batch) then
      failwith "fixed replay differs";
    let planner workers () =
      let rows = ref [] in
      let result =
        P.execute plan ~workers ~cancellation:(Planner.cancellation ())
          ~sink:(function
          | P.Row r ->
              rows := r.outcomes :: !rows;
              Ok ()
          | P.Finished _ -> Ok ())
      in
      I.complete n result;
      let expected =
        Array.to_list
          (Array.map
             (fun (r : B.row) -> List.map I.convert r.outcomes)
             reference)
      in
      if I.payload (List.rev !rows) <> I.payload expected then
        failwith "planner replay differs"
    in
    List.iter (fun w -> planner w ()) (if !size = 1 then [ 1 ] else [ 1; 4 ]);
    let measured_planner workers () =
      let first = ref 0. and start = clock () in
      let c =
        P.execute plan ~workers ~cancellation:(Planner.cancellation ())
          ~sink:(function
          | P.Row _ ->
              if !first = 0. then first := clock () -. start;
              Ok ()
          | P.Finished _ -> Ok ())
      in
      I.complete n c;
      !first
    in
    let methods =
      [
        ( "admission",
          fun () ->
            ignore (Sys.opaque_identity (requests ()));
            0. );
        ( "scalar",
          fun () ->
            ignore (Sys.opaque_identity (scalar ()));
            0. );
        ( "batch",
          fun () ->
            ignore (Sys.opaque_identity (B.execute batch));
            0. );
      ]
      @ List.map
          (fun w -> ("planner" ^ string_of_int w, measured_planner w))
          (if !size = 1 then [ 1 ] else [ 1; 4 ])
    in
    let methods = if !reverse then List.rev methods else methods in
    List.iter
      (fun (name, f) ->
        ignore (f ());
        Gc.full_major ();
        let start = clock () in
        let first = f () in
        Printf.printf "TIME\t%s\t%.17g\t%.17g\n%!" name
          (clock () -. start)
          first)
      methods;
    List.iter
      (fun (name, f) ->
        let before = I.total_bytes (Gc.stat ()) in
        ignore (f ());
        let after = I.total_bytes (Gc.stat ()) in
        Printf.printf "MEMORY\t%s\t%.0f\n%!" name (after -. before))
      methods;
    let compile name f =
      ignore (f ());
      let start = clock () in
      for _ = 1 to 50 do
        ignore (Sys.opaque_identity (f ()))
      done;
      Printf.printf "COMPILE\t%s\t%.17g\n%!" name ((clock () -. start) /. 50.)
    in
    compile "batch" batch_compile;
    compile "planner" plan_compile;
    Printf.printf "COMPLETE\t%s\t%d\t%d\n%!" !case !size n

let () =
  try main ()
  with e ->
    prerr_endline (Printexc.to_string e);
    exit 2
