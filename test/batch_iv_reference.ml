open Morphiq_risk

let check (type i c) (model : (i, c) Batch.model)
    (module M : Production.MODEL with type inputs = i and type coordinate = c)
    inputs side quote expected reference =
  let request = Batch.Request (model, inputs, side, Batch.Implied quote) in
  let got = Batch.evaluate request in
  let scalar =
    match M.admit inputs with
    | Error e -> Error e
    | Ok a -> M.implied a side quote
  in
  if Marshal.to_string got [] <> Marshal.to_string scalar [] then
    failwith "batch IV scalar mismatch";
  match got with
  | Ok (Iv.Root root) when expected = "root" ->
      if
        Int64.bits_of_float (Vol.to_float root) <> Int64.bits_of_float reference
      then failwith "batch IV independent root mismatch"
  | _ -> ()

let () =
  let count = ref 0 in
  Oracle_fixture.lines ~columns:[ 16 ] ~names:[ "iv" ] Sys.argv.(1)
  |> List.iter (fun line ->
         if line <> "" && line.[0] <> '#' then
           Scanf.sscanf line
             "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
             (fun
               model
               side
               expected
               _parameter
               s
               k
               t
               r
               q
               _seed
               shift
               quote
               _lo
               _hi
               reference
               _ferro
             ->
               incr count;
               let f = Int64.float_of_bits in
               let s, k, t, r, q, shift, quote, reference =
                 (f s, f k, f t, f r, f q, f shift, f quote, f reference)
               in
               let side = if side = "call" then Side.Call else Side.Put in
               match model with
               | "bsm" ->
                   check Batch.Bsm
                     (module Production.Bsm)
                     Black.Bsm_carry.
                       {
                         spot = s;
                         strike = k;
                         time_to_expiry = t;
                         rate = r;
                         dividend_yield = q;
                       }
                     side quote expected reference
               | "black76" ->
                   check Batch.Black76
                     (module Production.Black76)
                     Black.Black76_carry.
                       { forward = s; strike = k; time_to_expiry = t; rate = r }
                     side quote expected reference
               | "displaced" ->
                   check Batch.Displaced
                     (module Production.Displaced)
                     Black.Displaced_carry.
                       {
                         forward = s;
                         strike = k;
                         displacement = shift;
                         time_to_expiry = t;
                         rate = r;
                       }
                     side quote expected reference
               | "bachelier" ->
                   check Batch.Bachelier
                     (module Production.Bachelier)
                     Bachelier.
                       { forward = s; strike = k; time_to_expiry = t; rate = r }
                     side quote expected reference
               | _ -> failwith "unknown fixture model"));
  if !count <> 8330 then failwith "unexpected IV fixture coverage";
  Printf.printf
    "%d batch IV fixture outcomes equal scalar; served roots equal independent \
     reference\n"
    !count
