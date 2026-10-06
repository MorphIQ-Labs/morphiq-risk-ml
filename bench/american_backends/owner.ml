(* Experiment-only policy adapter; build.py installs this in an isolated tree. *)
module O = American_policy_original
module R = American_policy_reference
module BA = Bigarray.Array1

type phase = O.phase = Select | Eliminate | Substitute | Copy

let mode =
  match Sys.getenv_opt "MORPHIQ_POLICY_BACKEND" with
  | None | Some "native" -> "native"
  | Some (("ocaml" | "lapack") as x) -> x
  | Some _ -> invalid_arg "unknown experimental policy backend"

let account = Sys.getenv_opt "MORPHIQ_POLICY_ACCOUNT" = Some "1"
let native_bytes = Atomic.make 0
let owners = Atomic.make 0

let () =
  if account then
    at_exit (fun () ->
        Printf.eprintf "NATIVE_ALLOC\t%d\t%d\n%!" (Atomic.get native_bytes)
          (Atomic.get owners))

let trace = Option.map open_out (Sys.getenv_opt "MORPHIQ_POLICY_TRACE")
let () = Option.iter (fun out -> at_exit (fun () -> close_out out)) trace
let ordinals = Hashtbl.create 8
let wanted = [ 1; 2; 8; 32; 128; 512 ]

type t = {
  native : O.t;
  bands : float array array;
  flags : bool array array;
  state : int array;
  scratch : (float, Bigarray.float64_elt, Bigarray.c_layout) BA.t;
  mutable count : int;
  mutable pending : (int * float array array * bool array * float) option;
  mutable allowance : float;
}

external solve :
  float array array ->
  bool array ->
  (float, Bigarray.float64_elt, Bigarray.c_layout) BA.t ->
  int = "morphiq_experiment_dgtsv"

let create ~lo ~diag ~hi ~rhs ~values ~payoff ~pivots ~solution_rhs ~candidate
    ~mask ~oldmask =
  let native =
    O.create ~lo ~diag ~hi ~rhs ~values ~payoff ~pivots ~solution_rhs ~candidate
      ~mask ~oldmask
  in
  if account && mode = "lapack" then (
    ignore (Atomic.fetch_and_add native_bytes (32 * (Array.length lo - 2)));
    ignore (Atomic.fetch_and_add owners 1));
  {
    native;
    bands =
      [| lo; diag; hi; rhs; values; payoff; pivots; solution_rhs; candidate |];
    flags = [| mask; oldmask |];
    state = [| 0; 0; 0; 17; 0 |];
    scratch =
      BA.create Bigarray.float64 Bigarray.c_layout
        (if mode = "lapack" then 4 * (Array.length lo - 2) else 0);
    count = 0;
    pending = None;
    allowance = 0.;
  }

let context t ~local = t.allowance <- local
let reset t ~obstacle = O.reset t.native ~obstacle
let changed t = O.changed t.native
let fingerprint t = O.fingerprint t.native
let visited t = t.count

let snapshot t =
  match trace with
  | None -> ()
  | Some _ ->
      if not (Domain.is_main_domain ()) then
        invalid_arg "capture requires the main domain";
      let n = Array.length t.bands.(0) - 2 in
      let ordinal = 1 + Option.value ~default:0 (Hashtbl.find_opt ordinals n) in
      Hashtbl.replace ordinals n ordinal;
      if List.mem ordinal wanted then
        let mask = t.flags.(0) in
        let a =
          Array.init 4 (fun k ->
              Array.init n (fun j ->
                  let i = j + 1 in
                  match k with
                  | 0 -> if j = 0 || mask.(i) then 0. else t.bands.(0).(i)
                  | 1 -> t.bands.(6).(i)
                  | 2 -> if j = n - 1 || mask.(i) then 0. else t.bands.(2).(i)
                  | _ -> t.bands.(7).(i)))
        in
        t.pending <- Some (ordinal, a, Array.sub mask 1 n, t.allowance)

let publish t =
  match (trace, t.pending) with
  | Some out, Some (ordinal, a, mask, allowance) ->
      let n = Array.length mask in
      Printf.fprintf out "MATRIX\t%d\t%d\t%h\n" n ordinal allowance;
      for j = 0 to n - 1 do
        Printf.fprintf out "DATA\t%h\t%h\t%h\t%h\t%h\t%d\n"
          a.(0).(j)
          a.(1).(j)
          a.(2).(j)
          a.(3).(j)
          t.bands.(8).(j + 1)
          (if mask.(j) then 1 else 0)
      done;
      flush out;
      t.pending <- None
  | _ -> ()

let run t phase ~first ~last =
  if phase = Eliminate && first = 2 then snapshot t;
  let code =
    match (mode, phase) with
    | "ocaml", (Eliminate | Substitute) ->
        t.state.(0) <- (if phase = Eliminate then 1 else 2);
        let result = R.run t.bands t.flags t.state ~first ~last in
        t.count <- t.state.(4);
        result
    | "lapack", (Eliminate | Substitute) ->
        t.count <- abs (last - first) + 1;
        (* Cost proxy: whole-system work occurs at first elimination block.
         Subsequent block visits preserve accounting, NOT physical cancellation. *)
        if phase = Eliminate && first = 2 then
          solve t.bands t.flags.(0) t.scratch
        else 0
    | _ ->
        let result = O.run t.native phase ~first ~last in
        t.count <- O.visited t.native;
        result
  in
  if phase = Substitute && last = 1 && code = 0 then publish t;
  code
