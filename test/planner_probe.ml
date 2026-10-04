(* Test-only domain and result-lifetime observations. Configuration is frozen
   before execution; shared observations use atomics. *)
let spawned = Atomic.make 0
let joined = Atomic.make 0
let active = Atomic.make 0
let completed_tiles = Atomic.make 0
let retained_slots = Atomic.make 0
let peak_slots = Atomic.make 0
let attempts = ref 0
let fail_spawn = ref (-1)
let fail_domain = ref (-1)
let fail_tile = ref (-1)
let before_tile = ref (fun (_ : int) -> ())
let after_tile = ref (fun (_ : int) -> ())

let reset () =
  if Atomic.get active <> 0 || Atomic.get spawned <> Atomic.get joined then
    failwith "probe reset with unjoined domains";
  List.iter
    (fun x -> Atomic.set x 0)
    [ spawned; joined; active; completed_tiles; retained_slots; peak_slots ];
  attempts := 0;
  fail_spawn := -1;
  fail_domain := -1;
  fail_tile := -1;
  (before_tile := fun _ -> ());
  after_tile := fun _ -> ()

let rec maximum counter value =
  let previous = Atomic.get counter in
  if value > previous && not (Atomic.compare_and_set counter previous value)
  then maximum counter value

let retain count =
  let now = Atomic.fetch_and_add retained_slots count + count in
  maximum peak_slots now

let release_wave () = Atomic.set retained_slots 0

let evaluate id f =
  !before_tile id;
  if id = !fail_tile then failwith "injected tile failure";
  let result = f () in
  ignore (Atomic.fetch_and_add completed_tiles 1);
  !after_tile id;
  result

let await label predicate =
  let deadline = Unix.gettimeofday () +. 5. in
  while not (predicate ()) do
    if Unix.gettimeofday () > deadline then failwith ("deadline: " ^ label);
    Unix.sleepf 0.001
  done

module Domains = struct
  let spawn f =
    incr attempts;
    let attempt = !attempts in
    if attempt = !fail_spawn then failwith "injected spawn rejection";
    let domain =
      Domain.spawn (fun () ->
          ignore (Atomic.fetch_and_add active 1);
          Fun.protect
            ~finally:(fun () -> ignore (Atomic.fetch_and_add active (-1)))
            (fun () ->
              if attempt = !fail_domain then
                failwith "injected domain exception";
              f ()))
    in
    ignore (Atomic.fetch_and_add spawned 1);
    domain

  let join domain =
    Fun.protect
      ~finally:(fun () -> ignore (Atomic.fetch_and_add joined 1))
      (fun () -> Domain.join domain)
end
