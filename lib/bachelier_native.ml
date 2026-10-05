external kernel : int -> float array -> float array -> unit
  = "morphiq_bachelier_kernel"

external backend_id : unit -> int = "morphiq_bachelier_backend"

let backend = backend_id ()
let default_enabled = backend = 2

type t = { parameters : float array; values : Bachelier.Fast_middle.t array }

let compile values =
  let n = Array.length values in
  if n > Sys.max_array_length / 4 then invalid_arg "Bachelier kernel array size";
  let parameters = Array.make (4 * n) 0. in
  Array.iteri
    (fun i (p : Bachelier.Fast_middle.t) ->
      parameters.(i) <- p.q;
      parameters.(n + i) <- p.low;
      parameters.((2 * n) + i) <- p.s;
      parameters.((3 * n) + i) <- p.discount)
    values;
  (* Non-flat-array configurations use the typed scalar path. The ordinary
     supported compiler has flat float arrays and retains no second copy. *)
  { parameters; values = (if backend = 0 then Array.copy values else [||]) }

let length p = Array.length p.parameters / 4

let execute ?(scalar = false) p =
  if backend = 0 then Array.map Bachelier.Fast_middle.price p.values
  else
    let result = Array.make (length p) 0. in
    kernel (if scalar then 1 else 2) p.parameters result;
    result
