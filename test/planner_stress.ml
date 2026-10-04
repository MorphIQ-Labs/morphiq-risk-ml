open Morphiq_risk
module Public = Planner_stress_cases.Make (Planner)
module P = Planner_instrumented
module Cases = Planner_stress_cases.Make (P)
module Probe = Planner_probe

let check b message = if not b then failwith message
let ok = Cases.ok
let trace events = Marshal.to_string events []
let checks = ref 0
let observed_peak = ref 0

let joined () =
  check (Atomic.get Probe.active = 0) "active worker at sink/return";
  check (Atomic.get Probe.spawned = Atomic.get Probe.joined) "unjoined worker";
  observed_peak := max !observed_peak (Atomic.get Probe.peak_slots)

let bounded plan =
  joined ();
  check
    (Atomic.get Probe.peak_slots <= (P.explain plan).buffered_results)
    "observed result slots exceeded compiled bound";
  check (Atomic.get Probe.retained_slots = 0) "results retained after return";
  incr checks

let matrix () =
  let baseline, status = Public.run (Public.ok (Public.make 1)) in
  Public.verify 17 3 baseline status;
  List.iter
    (fun tile_rows ->
      List.iter
        (fun workers ->
          let public_plan = Public.ok (Public.make tile_rows) in
          let public, status = Public.run ~workers public_plan in
          Public.verify 17 3 public status;
          check (trace public = trace baseline) "public worker/tile replay";
          Probe.reset ();
          let plan = ok (Cases.make tile_rows) in
          check
            (P.manifest plan = Planner.manifest public_plan)
            "instrumented plan identity";
          let events, status =
            Cases.run ~workers
              ~sink:(fun _ ->
                joined ();
                Ok ())
              plan
          in
          Cases.verify 17 3 events status;
          check (trace events = trace baseline) "instrumented/public replay";
          bounded plan)
        [ 1; 2; 3; 4 ])
    [ 1; 2; 5; 19 ];
  List.iter
    (fun (count, scenario_count, empty_outputs) ->
      Probe.reset ();
      let plan = ok (Cases.make ~count ~scenario_count ~empty_outputs 2) in
      let events, status = Cases.run ~workers:4 plan in
      Cases.verify count scenario_count events status;
      bounded plan)
    [ (0, 3, false); (17, 0, false); (0, 0, false); (17, 3, true) ];
  let plan = ok (Cases.make 2) in
  let limits = (P.explain plan).limits and ex = P.explain plan in
  List.iter
    (fun (label, exact, below) ->
      check
        (Result.is_ok (Cases.make ~limits:exact 2))
        (label ^ " exact rejected");
      check
        (Result.is_error (Cases.make ~limits:below 2))
        (label ^ " under-limit accepted");
      incr checks)
    [
      ("instruments", limits, { limits with max_instruments = 16 });
      ("scenarios", limits, { limits with max_scenarios = 2 });
      ( "calculations",
        limits,
        { limits with max_calculations = ex.calculations - 1 } );
      ( "slots",
        { limits with max_buffered_results = ex.buffered_results },
        { limits with max_buffered_results = ex.buffered_results - 1 } );
      ( "groups",
        { limits with max_groups = ex.groups },
        { limits with max_groups = ex.groups - 1 } );
    ];
  let huge =
    ok (Scenario.linear ~first:100. ~step:0. ~count:((1 lsl 53) - 1))
  in
  let scenarios =
    ok
      (Scenario.cartesian
         [
           Scenario.Market
             { factor = "s"; field = Spot; mode = Absolute; range = huge };
         ])
  in
  let overflow =
    P.compile ~snapshot_id:"overflow" ~base_day:0 ~day_count:P.Actual_365_fixed
      ~portfolio:(Cases.portfolio 17) ~market:Cases.market ~scenarios
      ~lognormal_outputs:(Cases.outputs false)
      ~normal_outputs:(Cases.outputs false) ~output_mode:P.Stream
      ~limits:
        { limits with max_scenarios = max_int; max_calculations = max_int }
  in
  check (overflow = Error "cardinality overflow") "raw-volume overflow";
  List.iter
    (fun index ->
      check
        (try
           ignore (P.tile plan index);
           false
         with Invalid_argument _ -> true)
        "invalid tile index")
    [ -1; ex.tiles ];
  let tile = P.tile plan 0 in
  check
    (Result.is_error
       (P.evaluate_tile plan { tile with length = tile.length + 1 }))
    "invalid extent";
  check
    (Result.is_error (P.evaluate_tile (ok (Cases.make 3)) tile))
    "foreign tile";
  (* Test-only records are deliberately unsealed; the public tile remains private. *)
  Probe.release_wave ()

let fault configure expected_rows expected_calculations =
  Probe.reset ();
  configure ();
  let plan = ok (Cases.make 2) in
  let events, status =
    Cases.run ~workers:4
      ~sink:(fun _ ->
        joined ();
        Ok ())
      plan
  in
  bounded plan;
  check
    (match status.stop with P.Worker_failure _ -> true | _ -> false)
    "fault declared complete";
  check
    (status.rows_committed = expected_rows
    && status.calculations_committed = expected_calculations)
    "fault accounting";
  let rows =
    List.filter_map (function P.Row row -> Some row | _ -> None) events
  in
  List.iteri
    (fun i row ->
      check (row.P.instrument_index = i && row.scenario_id = 0) "fault prefix")
    rows;
  check (List.length rows = expected_rows) "fault delivered count";
  check
    (List.for_all (function P.Summary _ -> false | _ -> true) events)
    "interrupted scenario summary";
  check
    (match List.rev events with P.Finished c :: _ -> c = status | _ -> false)
    "fault terminal marker"

let faults () =
  fault (fun () -> Probe.fail_spawn := 1) 0 0;
  fault (fun () -> Probe.fail_spawn := 2) 0 0;
  fault (fun () -> Probe.fail_spawn := 5) 8 24;
  fault (fun () -> Probe.fail_tile := 0) 0 0;
  fault (fun () -> Probe.fail_tile := 2) 4 12;
  fault (fun () -> Probe.fail_domain := 2) 4 12

let slow_and_cancel () =
  Probe.reset ();
  let plan = ok (Cases.make 2) in
  let overtaken = Atomic.make false in
  (Probe.before_tile :=
     fun id ->
       if id = 0 then (
         Probe.await "later tiles finish before first" (fun () ->
             Atomic.get Probe.completed_tiles >= 3);
         Atomic.set overtaken true));
  let snapshots = ref 0 in
  let events, status =
    Cases.run ~workers:4
      ~sink:(fun _ ->
        joined ();
        let spawned = Atomic.get Probe.spawned in
        Unix.sleepf 0.0005;
        check
          (spawned = Atomic.get Probe.spawned)
          "dispatch continued during sink";
        incr snapshots;
        Ok ())
      plan
  in
  Cases.verify 17 3 events status;
  check
    (Atomic.get overtaken && !snapshots > 0)
    "slow-first schedule not reached";
  bounded plan;
  (* A real second domain cancels while the coordinator's first tile waits. *)
  Probe.reset ();
  let cancellation = P.cancellation () in
  let entered = Atomic.make false and released = Atomic.make false in
  (Probe.before_tile :=
     fun id ->
       if id = 0 then (
         Atomic.set entered true;
         Probe.await "external cancellation" (fun () -> Atomic.get released)));
  let controller =
    Domain.spawn (fun () ->
        Probe.await "first tile entered" (fun () -> Atomic.get entered);
        P.cancel cancellation;
        Atomic.set released true)
  in
  let events = ref [] in
  let status =
    Fun.protect
      ~finally:(fun () -> Domain.join controller)
      (fun () ->
        P.execute plan ~workers:4 ~cancellation ~sink:(fun e ->
            joined ();
            events := e :: !events;
            Ok ()))
  in
  bounded plan;
  check
    (status.stop = P.Cancelled && status.rows_committed = 0)
    "running-wave cancellation";
  check (!events = [ P.Finished status ]) "cancelled wave emitted rows";
  (* Cancellation on each row boundary, including scenario and final boundaries. *)
  List.iter
    (fun at ->
      Probe.reset ();
      let cancellation = P.cancellation () in
      let accepted = ref 0 and summaries = ref [] in
      let status =
        P.execute plan ~workers:4 ~cancellation ~sink:(fun event ->
            joined ();
            (match event with
            | P.Row _ ->
                incr accepted;
                if !accepted = at then P.cancel cancellation
            | P.Summary s -> summaries := s.scenario_id :: !summaries
            | _ -> ());
            Ok ())
      in
      bounded plan;
      check
        (status.rows_committed = at && !accepted = at
        && status.calculations_committed = at * 3)
        "cancel row accounting";
      check
        (status.stop = if at = 51 then P.Complete else P.Cancelled)
        "cancel stop boundary";
      check
        (List.sort_uniq compare !summaries = List.init (at / 17) Fun.id)
        "cancel summaries")
    [ 1; 8; 17; 50; 51 ]

let sinks () =
  List.iter
    (fun raised ->
      List.iter
        (fun kind ->
          Probe.reset ();
          let plan = ok (Cases.make 2) in
          let stopped = ref false and accepted = ref 0 and rejected = ref 0 in
          let status =
            P.execute plan ~workers:4 ~cancellation:(P.cancellation ())
              ~sink:(fun event ->
                joined ();
                check (not !stopped) "callback after broken sink";
                let target =
                  match event with
                  | P.Row _ -> kind = "row" && !accepted = 9
                  | P.Summary _ -> kind = "summary"
                  | P.Finished _ -> kind = "finished"
                in
                if target then (
                  stopped := true;
                  incr rejected;
                  if raised then failwith "raised sink"
                  else Error "returned sink")
                else (
                  (match event with P.Row _ -> incr accepted | _ -> ());
                  Ok ()))
          in
          bounded plan;
          check
            (!rejected = 1
            && status.rows_committed = !accepted
            && status.calculations_committed = !accepted * 3)
            "sink committed prefix";
          check
            (match status.stop with P.Sink_failure _ -> true | _ -> false)
            "sink failure classification")
        [ "row"; "summary"; "finished" ])
    [ false; true ]

let memory count scenarios =
  (* Public executor, streaming consumer, no retained event trace. *)
  let plan = Public.ok (Public.make ~count ~scenario_count:scenarios 32) in
  let status =
    Planner.execute plan ~workers:4 ~cancellation:(Planner.cancellation ())
      ~sink:(fun _ -> Ok ())
  in
  check
    (status.stop = Planner.Complete && status.rows_committed = count * scenarios)
    "memory run completion";
  let ex = Planner.explain plan in
  Printf.printf
    "{\"book\":%d,\"scenarios\":%d,\"rows\":%d,\"slot_bound\":%d,\"heap_words\":%d}\n"
    count scenarios status.rows_committed ex.buffered_results
    (Gc.stat ()).heap_words

let () =
  match Array.to_list Sys.argv with
  | [ _; "--memory"; count; scenarios ] ->
      memory (int_of_string count) (int_of_string scenarios)
  | [ _ ] ->
      matrix ();
      faults ();
      slow_and_cancel ();
      sinks ();
      Printf.printf
        "{\"checks\":%d,\"peak_observed_slots\":%d,\"planner_source_sha256\":%S,\"ocaml\":%S}\n"
        !checks !observed_peak P.instrumented_source_sha256 Sys.ocaml_version
  | _ -> failwith "usage: planner_stress.exe [--memory BOOK SCENARIOS]"
