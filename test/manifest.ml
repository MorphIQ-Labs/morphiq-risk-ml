(* Verifies oracle/MANIFEST (written by oracle/write_manifest.py): each
   fixture's bytes, and its generator's and common.py's, must still hash to
   the recorded BLAKE2b-256. A changed generator without a regenerated
   fixture fails here. *)

let blake path = Digest.BLAKE256.to_hex (Digest.BLAKE256.file path)

let () =
  let oracle = Sys.argv.(1) in
  let file name = Filename.concat oracle name in
  let problems = ref [] and checked = ref 0 in
  let seen = Hashtbl.create 16 in
  let check name what path recorded =
    if not (Sys.file_exists path) then
      problems := Printf.sprintf "%s: %s is missing" name what :: !problems
    else if blake path <> recorded then
      problems :=
        Printf.sprintf "%s: %s changed since the fixture was generated%s" name
          what
          (if what = "fixture" then "" else "; run oracle/build.sh " ^ name)
        :: !problems
  in
  In_channel.with_open_text (file "MANIFEST") In_channel.input_lines
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           match String.split_on_char ' ' line with
           | name :: generator :: generator_hash :: common_hash :: _mpmath
             :: _python :: _rows :: fixture_hash :: dependencies ->
               if Hashtbl.mem seen name then
                 problems := ("duplicate fixture: " ^ name) :: !problems;
               Hashtbl.replace seen name ();
               incr checked;
               check name generator (file generator) generator_hash;
               check name "common.py" (file "common.py") common_hash;
               check name "fixture"
                 (file (Filename.concat "fixtures" (name ^ ".txt.gz")))
                 fixture_hash;
               List.iter
                 (fun dependency ->
                   match String.split_on_char ':' dependency with
                   | [ path; hash ] -> check name path (file path) hash
                   | _ ->
                       problems :=
                         ("malformed dependency: " ^ dependency) :: !problems)
                 dependencies
           | _ -> problems := ("malformed line: " ^ line) :: !problems);
  Sys.readdir (file "fixtures")
  |> Array.iter (fun filename ->
         if Filename.check_suffix filename ".txt.gz" then
           let name = Filename.chop_suffix filename ".txt.gz" in
           if not (Hashtbl.mem seen name) then
             problems := ("missing fixture record: " ^ name) :: !problems);
  List.iter print_endline (List.rev !problems);
  Printf.printf "%d fixtures checked, %d problems\n" !checked
    (List.length !problems);
  if !problems <> [] || !checked = 0 then exit 1
