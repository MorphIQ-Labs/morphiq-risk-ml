(* The mutation catalog: every numerical mechanism the docs claim, removed.

   The type system already rejects the structural mistakes (test/types). What
   it cannot see is a well-typed numerical mistake: [Split.two_sum a b] and
   [(a +. b, 0.0)] have the same type. Each mutant here removes one such
   mechanism and names the test that must fail without it.

   A mutant replaces one exact snippet (it must occur exactly once, so a
   catalog that drifts from the code fails loudly). It counts as killed only
   when it compiles (a compiler rejection proves nothing about the tests) and
   the named test fails (so the kill comes from the oracle or property that
   guards the mechanism).

   The suite runs under the [mutation] dune profile, which disables the
   determinism digest (any numerical change trips it) and leaves warnings
   non-fatal. Work happens in a temporary copy of the tracked files; the
   checkout is never modified.

     dune exec scripts/mutation/mutation.exe              run the catalog
     dune exec scripts/mutation/mutation.exe -- --list    print it
     dune exec scripts/mutation/mutation.exe -- ID ...    run the named mutants *)

type mutant = {
  id : string;
  file : string;
  snippet : string;
  replacement : string;
  killer : string;  (** The test that must fail. *)
  mechanism : string;
}

(* Two mechanisms are justified by the error analysis but cannot be decided
   by a test, so they are not here. Each lowers a certified bound by less than
   the certified slack the rest of the computation already carries, so no
   input can make its removal violate a bound (docs/error-analysis.md §5.1):

   - ln(S/K)'s quotient remainder in double-word: it removes a u^2 term from
     x's bound, below ln q's own certified error.
   - The intrinsic's branch rule (x's terms <= 1): it picks whichever of
     C expm1(x) and A - C has the smaller certified error; the other branch's
     realized error stays inside the chosen one's bound. *)
let catalog =
  [
    {
      id = "floor-exponent";
      file = "lib/black.ml";
      snippet = "(snd (Float.frexp spot) + snd (Float.frexp strike)) asr 1";
      replacement = "(snd (Float.frexp spot) + snd (Float.frexp strike)) / 2";
      killer = "properties";
      mechanism = "floor-divided scale exponent (exact homogeneity)";
    };
    {
      id = "intrinsic-expm1";
      file = "lib/black.ml";
      snippet =
        "if Float.abs c.x <= 0.35 && c.x_terms <= 1.0 then Dd.mul cash \
         (Dd.expm1 x)";
      replacement = "if false then Dd.mul cash (Dd.expm1 x)";
      killer = "oracle_price";
      mechanism = "near-the-money intrinsic as C expm1(x)";
    };
    {
      id = "root-time-low";
      file = "lib/black.ml";
      snippet = "root_time_low = snd (Split.sqrt time);";
      replacement = "root_time_low = 0.0;";
      killer = "oracle_price";
      mechanism = "sqrt T, and so s = sigma sqrt T, in double-double";
    };
    {
      id = "subnormal-rounding";
      file = "lib/dd.ml";
      snippet =
        "if Float.abs v >= Float.min_float || a.hi = 0.0 || not \
         (Float.is_finite v)";
      replacement = "if true";
      killer = "test_morphiq_risk";
      mechanism = "one rounding into the subnormals (Dd.to_float_scaled)";
    };
    {
      id = "displaced-exact-sum";
      file = "lib/black.ml";
      snippet =
        "let f, fl = Split.two_sum i.forward i.displacement\n\
        \          and k, kl = Split.two_sum i.strike i.displacement in";
      replacement =
        "let f, fl = (i.forward +. i.displacement, 0.0)\n\
        \          and k, kl = (i.strike +. i.displacement, 0.0) in";
      killer = "oracle_price";
      mechanism = "displaced Black on the exact sums F + d, K + d";
    };
    {
      id = "bachelier-distance";
      file = "lib/bachelier.ml";
      snippet = "Split.two_sum i.forward (-.i.strike)";
      replacement = "(i.forward -. i.strike, 0.0)";
      killer = "oracle_price";
      mechanism = "Bachelier F - K with its remainder";
    };
    {
      id = "gaussian-split";
      file = "lib/normal.ml";
      snippet = "Split.scaled_exp_neg scale (0.5 *. hi) (0.5 *. lo)";
      replacement = "Split.scaled_exp_neg scale (0.5 *. hi) 0.0";
      killer = "oracle_normal";
      mechanism = "exact split of u^2 in exp(-u^2/2)";
    };
    {
      id = "log1p-remainder";
      file = "lib/elementary.ml";
      snippet = "let d, dl = two_sum 2.0 f in";
      replacement = "let d, dl = (2.0 +. f, 0.0) in";
      killer = "oracle_elementary";
      mechanism = "log1p's quotient remainder";
    };
    {
      id = "dd-exp-threshold";
      file = "lib/dd.ml";
      snippet = "inv_k *. 0x1p-104";
      replacement = "inv_k *. epsilon_float";
      killer = "dd_reference";
      mechanism = "QD's 2^-104 stopping rule in the double-double exp";
    };
    {
      id = "normal-dd-series";
      file = "lib/normal_dd.ml";
      snippet = "Float.abs term.Dd.hi <= 0x1p-110 *. Float.abs acc.Dd.hi";
      replacement = "Float.abs term.Dd.hi <= 0x1p-60 *. Float.abs acc.Dd.hi";
      killer = "normal_dd_reference";
      mechanism = "Marsaglia's series to double-double precision";
    };
    {
      id = "iv-rounded-bound";
      file = "lib/black.ml";
      snippet = "if p = intrinsic.hi then root 0.0 else Iv.Below_intrinsic";
      replacement = "if false then root 0.0 else Iv.Below_intrinsic";
      killer = "oracle_iv";
      mechanism = "a quote equal to the rounded intrinsic is sigma = 0 (#448)";
    };
    {
      id = "iv-beta-bar";
      file = "lib/black.ml";
      snippet = "Dd.to_float (Dd.div (Dd.sub maximum (Dd.of_float p)) m_dd)";
      replacement = "Elementary.exp (0.5 *. x) -. beta";
      killer = "oracle_iv";
      mechanism = "beta-bar from the exact distance to the maximum";
    };
    {
      id = "iv-ln-beta";
      file = "lib/black.ml";
      snippet =
        "(if intrinsic.hi > 0.0 then Elementary.log (Dd.to_float otm)\n\
        \         else Elementary.log price -. (float c.exponent *. \
         Split.ln2_hi))\n\
        \        -. Elementary.log m";
      replacement = "Elementary.log beta";
      killer = "oracle_iv";
      mechanism = "ln beta from the unscaled quote";
    };
    {
      id = "iv-complement-correction";
      file = "lib/black.ml";
      snippet = "else if beta > 0.5 *. b_max then";
      replacement = "else if false then";
      killer = "oracle_iv";
      mechanism = "the final Newton step on the complement near the maximum";
    };
    {
      id = "greeks-theta-dd";
      file = "lib/black.ml";
      snippet =
        "if\n\
        \        Float.abs d1_dd.Dd.hi <= Normal_dd.limit\n\
        \        && Float.abs d2_dd.Dd.hi <= Normal_dd.limit\n\
        \      then";
      replacement = "if false then";
      killer = "oracle_greeks";
      mechanism = "Black theta in double-double near the money";
    };
    {
      id = "greeks-charm-dd";
      file = "lib/black.ml";
      snippet = "if Float.abs d1_dd.Dd.hi <= Normal_dd.limit then charm_dd ()";
      replacement = "if false then charm_dd ()";
      killer = "oracle_greeks";
      mechanism = "Black charm's bracket in double-double";
    };
    {
      id = "greeks-veta-bracket";
      file = "lib/black.ml";
      snippet =
        "(Dd.sub (Dd.mul q_plus_d1_w rt_dd) (Dd.div (Dd.of_float 0.5) rt_dd))";
      replacement =
        "(Dd.of_float ((Dd.to_float q_plus_d1_w *. rt) -. (0.5 /. rt)))";
      killer = "oracle_greeks";
      mechanism = "veta's sqrt(T)-scaled bracket in double-double";
    };
    {
      id = "bachelier-theta-dd";
      file = "lib/bachelier.ml";
      snippet =
        "if Float.abs dh <= Normal_dd.limit then\n\
        \            let d_dd = { Dd.hi = dh; lo = dl } in";
      replacement =
        "if false then\n            let d_dd = { Dd.hi = dh; lo = dl } in";
      killer = "oracle_greeks";
      mechanism = "Bachelier theta in double-double near the money";
    };
  ]

(* Process plumbing. *)

(* A dune started from [dune exec] inherits variables that tell it it is
   nested; the child builds an independent tree, so they are dropped. *)
let child_env () =
  Unix.environment () |> Array.to_list
  |> List.filter (fun v ->
         not
           (String.starts_with ~prefix:"INSIDE_DUNE=" v
           || String.starts_with ~prefix:"DUNE_" v))
  |> Array.of_list

(* Runs [prog args] in [cwd]; returns the exit code and combined output. *)
let run ~cwd prog args =
  let log = Filename.temp_file "mutation" ".log" in
  let fd = Unix.openfile log [ O_WRONLY; O_TRUNC ] 0o600 in
  let previous = Sys.getcwd () in
  Sys.chdir cwd;
  let pid =
    Unix.create_process_env prog
      (Array.of_list (prog :: args))
      (child_env ()) Unix.stdin fd fd
  in
  Sys.chdir previous;
  Unix.close fd;
  let _, status = Unix.waitpid [] pid in
  let output = In_channel.with_open_bin log In_channel.input_all in
  Sys.remove log;
  let code =
    match status with WEXITED c -> c | WSIGNALED _ | WSTOPPED _ -> 255
  in
  (code, output)

let dune ~cwd args =
  run ~cwd "dune" (args @ [ "--root"; "."; "--profile"; "mutation" ])

let rec mkdir_p dir =
  if not (Sys.file_exists dir) then (
    mkdir_p (Filename.dirname dir);
    Sys.mkdir dir 0o755)

let read path = In_channel.with_open_bin path In_channel.input_all

let write path text =
  Out_channel.with_open_bin path (fun oc -> output_string oc text)

(* The tracked files, copied into a fresh directory. *)
let copy_tree root =
  let code, listing = run ~cwd:root "git" [ "ls-files" ] in
  if code <> 0 then failwith "git ls-files failed";
  let dest = Filename.temp_dir "mutation" "" in
  String.split_on_char '\n' listing
  |> List.iter (fun name ->
         if name <> "" then (
           let target = Filename.concat dest name in
           mkdir_p (Filename.dirname target);
           write target (read (Filename.concat root name))));
  dest

(* Occurrences of [needle] in [hay]. *)
let count needle hay =
  let n = String.length needle and m = String.length hay in
  let rec go i acc =
    if i > m - n then acc
    else if String.sub hay i n = needle then go (i + n) (acc + 1)
    else go (i + 1) acc
  in
  if n = 0 then 0 else go 0 0

let replace needle by hay =
  let n = String.length needle in
  let rec find i = if String.sub hay i n = needle then i else find (i + 1) in
  let i = find 0 in
  String.sub hay 0 i ^ by ^ String.sub hay (i + n) (String.length hay - i - n)

(* The tests dune reports as failed: each failure cites its stanza's
   "(name <test>)" line. *)
let failed_tests output =
  let key = "(name " in
  let k = String.length key in
  let rec scan i acc =
    match String.index_from_opt output i '(' with
    | None -> acc
    | Some j when j + k <= String.length output && String.sub output j k = key
      ->
        let stop = String.index_from output (j + k) ')' in
        scan stop (String.sub output (j + k) (stop - j - k) :: acc)
    | Some j -> scan (j + 1) acc
  in
  List.sort_uniq compare (scan 0 [])

(* Symbolic links (dune's _build/.../latest) are removed, not followed. *)
let rec remove_tree path =
  if (Unix.lstat path).st_kind = Unix.S_DIR then (
    Array.iter
      (fun f -> remove_tree (Filename.concat path f))
      (Sys.readdir path);
    Sys.rmdir path)
  else Sys.remove path

let score work m =
  let path = Filename.concat work m.file in
  let source = read path in
  match count m.snippet source with
  | 1 ->
      write path (replace m.snippet m.replacement source);
      Fun.protect
        ~finally:(fun () -> write path source)
        (fun () ->
          match dune ~cwd:work [ "build" ] with
          | c, _ when c <> 0 ->
              Error (Printf.sprintf "INVALID   %s: does not compile" m.id)
          | _ -> (
              match dune ~cwd:work [ "test" ] with
              | 0, _ ->
                  Error (Printf.sprintf "SURVIVED  %s: %s" m.id m.mechanism)
              | _, output ->
                  let failed = failed_tests output in
                  if List.mem m.killer failed then
                    let others = List.filter (( <> ) m.killer) failed in
                    Ok
                      (Printf.sprintf "killed    %s by %s%s" m.id m.killer
                         (if others = [] then ""
                          else " (also " ^ String.concat ", " others ^ ")"))
                  else
                    Error
                      (Printf.sprintf
                         "MISFIRED  %s: killed by [%s], expected %s" m.id
                         (String.concat ", " failed)
                         m.killer)))
  | n ->
      Error
        (Printf.sprintf "STALE     %s: snippet occurs %d times in %s" m.id n
           m.file)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  if args = [ "--list" ] then
    List.iter
      (fun m ->
        Printf.printf "%-26s %-20s %-20s %s\n" m.id m.file m.killer m.mechanism)
      catalog
  else
    let unknown =
      List.filter (fun a -> not (List.exists (fun m -> m.id = a) catalog)) args
    in
    if unknown <> [] then (
      prerr_endline ("unknown mutants: " ^ String.concat ", " unknown);
      exit 2);
    let selected =
      if args = [] then catalog
      else List.filter (fun m -> List.mem m.id args) catalog
    in
    (* dune exec runs from the workspace root. *)
    let work = copy_tree (Sys.getcwd ()) in
    let status =
      Fun.protect
        ~finally:(fun () -> remove_tree work)
        (fun () ->
          let start = Unix.gettimeofday () in
          match dune ~cwd:work [ "test" ] with
          | c, output when c <> 0 ->
              print_endline
                "baseline fails under the mutation profile; fix it before \
                 scoring mutants";
              print_string output;
              1
          | _ ->
              Printf.printf "baseline passes (%.0f s)\n%!"
                (Unix.gettimeofday () -. start);
              let bad =
                List.fold_left
                  (fun bad m ->
                    match score work m with
                    | Ok line ->
                        print_endline line;
                        flush stdout;
                        bad
                    | Error line ->
                        print_endline line;
                        flush stdout;
                        bad + 1)
                  0 selected
              in
              Printf.printf "%d of %d mutants killed as catalogued\n"
                (List.length selected - bad)
                (List.length selected);
              if bad = 0 then 0 else 1)
    in
    exit status
