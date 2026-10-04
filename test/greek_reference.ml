open Morphiq_risk

let () =
  let rows = ref 0 and failures = ref 0 and worst = ref 0.0 in
  Oracle_fixture.lines ~columns:[ 14 ] ~names:[ "greek_bits" ] Sys.argv.(1)
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line
             "%s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %d %Lx %Lx %Lx"
             (fun model side greek s k t r q sigma shift exponent h l tail ->
               let f = Int64.float_of_bits in
               let s = f s
               and k = f k
               and t = f t
               and r = f r
               and q = f q
               and sigma = f sigma
               and shift = f shift in
               let side = if side = "call" then Side.Call else Side.Put in
               let got =
                 match
                   Greek_values.greeks model side ~s ~k ~t ~r ~q ~sigma ~shift
                 with
                 | `Black g -> Greek_values.pick g greek
                 | `Normal g -> Greek_values.pick g greek
               in
               let got =
                 match got with
                 | Ok v -> v
                 | Error _ -> failwith "refused extended Greek reference"
               in
               Bounds.trace_float line got;
               let b =
                 if model = "bachelier" then
                   List.assoc greek
                     (Certified.bachelier ~side ~s ~k ~t ~r ~sigma ())
                 else
                   Certified.black model ~side ~s ~k ~t ~r ~q ~sigma ~shift
                     greek
               in
               let error =
                 Bounds.expansion_error
                   [ Float.ldexp got (-exponent); -.f h; -.f l; -.f tail ]
               in
               let bound =
                 Float.next_after
                   ((Float.ldexp b.e (-exponent) *. (1.0 +. (8.0 *. Bounds.u)))
                   +. 0x1p-158)
                   Float.infinity
               in
               incr rows;
               worst := Float.max !worst (error /. bound);
               if
                 (not (Certified.replay_matches got b))
                 || not (Bounds.within ~error ~bound)
               then (
                 incr failures;
                 if !failures <= 12 then
                   Printf.printf "%s: error %.5g radius %.5g | %s\n" greek error
                     bound line)));
  Printf.printf
    "%d extended Greek references, %d failures, worst %.5g of bound\n" !rows
    !failures !worst;
  if !rows = 0 || !failures <> 0 then exit 1
