open Morphiq_risk
module F = Batch.Fast

let () =
  let rows = Fast_reference_cases.load Sys.argv in
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
