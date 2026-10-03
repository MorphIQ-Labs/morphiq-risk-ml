open Morphiq_risk
module C = Internal.Certified_iv

module Check
    (E : Internal.Enclosure.S)
    (M : Internal.Model_enclosure.S with type scalar = E.t)
    (Solver : sig
      val solve :
        ?max_steps:int ->
        prepare_residual:(unit -> E.t -> E.t) ->
        intrinsic:E.t ->
        maximum:E.t option ->
        quote:float ->
        proposal:float ->
        unit ->
        C.outcome
    end) =
struct
  let require message ok = if not ok then failwith message
  let exact = E.exact

  let solve ?max_steps ?(intrinsic = exact 0.0) ?maximum ?(quote = 2.0)
      ?(proposal = 1.0) value =
    Solver.solve ?max_steps
      ~prepare_residual:(fun () -> fun x -> E.sub (value x) (exact quote))
      ~intrinsic ~maximum ~quote ~proposal ()

  let run () =
    require "certified square-root inverse"
      (solve (fun x -> E.mul x x) = C.Root (Float.sqrt 2.0));
    require "cap cannot manufacture a certified root"
      (solve ~max_steps:0 (fun x -> E.mul x x) = C.Non_convergence);
    require "uncertain evaluator cannot manufacture a root"
      (solve (fun _ -> E.add_error (exact 2.0) 1.0) = C.Numerical_failure);
    require "unresolved classification is not above maximum"
      (solve ~maximum:(E.add_error (exact 2.0) 0x1p-52) Fun.id
      = C.Numerical_failure);
    require "proved maximum is classified"
      (solve ~maximum:(exact 2.0) Fun.id = C.Above_maximum);
    require "proved intrinsic is classified"
      (solve ~intrinsic:(exact 3.0) Fun.id = C.Below_intrinsic);
    require "rounded-down intrinsic exception"
      (solve ~quote:1.0 ~intrinsic:(E.of_words 1.0 0x1p-54) Fun.id = C.Root 0.0);
    require "rounding does not erase a positive root"
      (solve ~quote:1.0 ~intrinsic:(E.of_words 1.0 (-0x1p-54)) ~proposal:0x1p-54
         (fun x -> E.add (E.of_words 1.0 (-0x1p-54)) x)
      = C.Root 0x1p-54);
    (* An exact halfway root selects the even endpoint, including when the
     proposal is the odd endpoint. The whole expression uses exact sums. *)
    let halfway = E.of_words 1.0 0x1p-53 in
    require "inverse midpoint ties to even"
      (solve ~quote:2.0 ~proposal:(Float.succ 1.0) (fun x ->
           E.add (exact 2.0) (E.sub x halfway))
      = C.Root 1.0);
    require "below-smallest requires a proved comparison"
      (solve ~quote:0x1p-1074 ~proposal:0x1p-1074 (fun x -> E.add x x)
      = C.Below_smallest_volatility);
    require "above-largest requires a proved comparison"
      (solve ~quote:Float.max_float (fun x -> E.scale x (-1)) = C.Above_maximum);
    require "the entire positive encoding terminates"
      (solve ~quote:Float.max_float Fun.id = C.Root Float.max_float);
    require "classification precedes residual construction"
      (Solver.solve
         ~prepare_residual:(fun () -> failwith "unneeded residual")
         ~intrinsic:(exact 3.0) ~maximum:None ~quote:1.0 ~proposal:1.0 ()
      = C.Below_intrinsic);
    let status = Hashtbl.create 16 in
    let accepted = ref 0 and attempted = ref 0 and root_index = ref 0 in
    let count key =
      Hashtbl.replace status key
        (1 + Option.value ~default:0 (Hashtbl.find_opt status key))
    in
    In_channel.with_open_text Sys.argv.(1) In_channel.input_lines
    |> List.iter (fun line ->
           if line <> "" && line.[0] <> '#' then
             Scanf.sscanf line
               "%s %s %s %s %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx %Lx"
               (fun
                 model
                 side
                 expected
                 _param
                 s
                 k
                 t
                 r
                 q
                 seed
                 shift
                 quote
                 _lo
                 _hi
                 reference
                 _ferro
               ->
                 let f = Int64.float_of_bits in
                 if expected = "root" then incr root_index;
                 (* The public oracle checks every root. This separate campaign
               deliberately supplies distant proposals to exercise bounded
               recovery; select a fixed stride across the complete corpus. *)
                 if expected = "root" && !root_index mod 67 = 0 then (
                   incr attempted;
                   let s, k, t, r, q, seed, shift, quote, reference =
                     ( f s,
                       f k,
                       f t,
                       f r,
                       f q,
                       f seed,
                       f shift,
                       f quote,
                       f reference )
                   in
                   let side = if side = "call" then Side.Call else Side.Put in
                   let result =
                     try
                       let prepared =
                         if model = "bachelier" then
                           M.normal ~forward:s ~strike:k ~time:t ~rate:r
                         else
                           let a = E.add (exact s) (exact shift)
                           and b = E.add (exact k) (exact shift) in
                           M.black ~spot:a.hi ~spot_low:a.lo ~strike:b.hi
                             ~strike_low:b.lo ~time:t ~rate:r
                             ~yield:(if model = "bsm" then q else r)
                       in
                       let intrinsic, maximum = M.bounds prepared side in
                       Solver.solve
                         ~prepare_residual:(fun () ->
                           M.inverse_residual prepared side quote)
                         ~intrinsic ~maximum ~quote
                         ~proposal:
                           (if seed > 0.0 && Float.is_finite seed then seed
                            else 1.0)
                         ()
                     with E.Unresolved _ -> C.Numerical_failure
                   in
                   match result with
                   | C.Root value ->
                       incr accepted;
                       if value <> reference then
                         failwith
                           (Printf.sprintf
                              "wrong certified root: %h expected %h | %s" value
                              reference line);
                       count (model ^ " certified")
                   | C.Numerical_failure -> count (model ^ " unresolved")
                   | C.Non_convergence ->
                       failwith
                         ("certified inverse exhausted discrete bound | " ^ line)
                   | _ ->
                       failwith
                         ("false certified mathematical classification | "
                        ^ line))));
    require "no certified reference roots" (!accepted > 0);
    Hashtbl.to_seq status |> List.of_seq |> List.sort compare
    |> List.iter (fun (key, n) -> Printf.printf "%s: %d\n" key n);
    Printf.printf
      "%d/%d exact-quote reference roots certified; unresolved rows are not \
       accuracy passes\n"
      !accepted !attempted
end

module Full = Check (Internal.Enclosure) (Internal.Model_enclosure) (C)

module First =
  Check (Internal.Enclosure.Fast) (Internal.Model_enclosure.Fast) (C.Fast)

let () =
  print_endline "Full inverse configuration";
  Full.run ();
  print_endline "First inverse configuration";
  First.run ()
