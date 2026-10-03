(* Optional out-of-process Runtime_events reader. Profiling is separate from
   ordinary timing; lost or unpaired events make the sample incomplete. *)
open Runtime_events

let () =
  if Array.length Sys.argv <> 4 then (
    prerr_endline "usage: gc_trace EVENT_DIRECTORY PID DONE_FILE";
    exit 2);
  let directory = Sys.argv.(1)
  and pid = int_of_string Sys.argv.(2)
  and done_file = Sys.argv.(3) in
  let active = Hashtbl.create 8
  and spans = ref []
  and lost = ref 0
  and unpaired = ref 0 in
  let selected = function EV_MINOR | EV_MAJOR -> true | _ -> false in
  let callbacks =
    Callbacks.create
      ~runtime_begin:(fun domain timestamp phase ->
        if selected phase then
          let key = (domain, phase) in
          let stack = Option.value ~default:[] (Hashtbl.find_opt active key) in
          Hashtbl.replace active key (Timestamp.to_int64 timestamp :: stack))
      ~runtime_end:(fun domain timestamp phase ->
        if selected phase then
          let key = (domain, phase) in
          match Hashtbl.find_opt active key with
          | Some (start :: rest) ->
              Hashtbl.replace active key rest;
              spans :=
                (domain, phase, start, Timestamp.to_int64 timestamp) :: !spans
          | _ -> incr unpaired)
      ~lost_events:(fun _ count -> lost := !lost + count)
      ()
  in
  let cursor = create_cursor (Some (directory, pid)) in
  print_endline "READY";
  flush stdout;
  while not (Sys.file_exists done_file) do
    ignore (read_poll cursor callbacks None);
    Unix.sleepf 0.001
  done;
  let rec drain () = if read_poll cursor callbacks None > 0 then drain () in
  drain ();
  free_cursor cursor;
  Hashtbl.iter (fun _ stack -> unpaired := !unpaired + List.length stack) active;
  List.iter
    (fun phase ->
      let durations =
        List.filter_map
          (fun (_, p, a, b) -> if p = phase then Some (Int64.sub b a) else None)
          !spans
        |> List.sort Int64.compare |> Array.of_list
      in
      let count = Array.length durations in
      let sum = Array.fold_left Int64.add 0L durations in
      let at q =
        if count = 0 then 0L
        else durations.(min (count - 1) (int_of_float (q *. float count)))
      in
      Printf.printf "%s\t%d\t%Ld\t%Ld\t%Ld\t%Ld\n" (runtime_phase_name phase)
        count sum (at 0.5) (at 0.99) (at 1.))
    [ EV_MINOR; EV_MAJOR ];
  let domains =
    List.map (fun (d, _, _, _) -> d) !spans |> List.sort_uniq Int.compare
  in
  List.iter
    (fun domain ->
      let intervals =
        List.filter_map
          (fun (d, _, a, b) -> if d = domain then Some (a, b) else None)
          !spans
        |> List.sort compare
      in
      let rec union sum current = function
        | [] -> (
            match current with
            | None -> sum
            | Some (a, b) -> Int64.add sum (Int64.sub b a))
        | (a, b) :: rest -> (
            match current with
            | None -> union sum (Some (a, b)) rest
            | Some (c, d) when a <= d -> union sum (Some (c, max b d)) rest
            | Some (c, d) ->
                union (Int64.add sum (Int64.sub d c)) (Some (a, b)) rest)
      in
      Printf.printf "UNION\t%d\t%Ld\n" domain (union 0L None intervals))
    domains;
  Printf.printf "INTEGRITY\t%d\t%d\n" !lost !unpaired;
  if !lost <> 0 || !unpaired <> 0 || !spans = [] then exit 1
