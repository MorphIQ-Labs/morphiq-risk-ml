type t = {
  bands : float array array;
  metrics : float array;
  indices : int array;
}

external compute :
  float array array -> int -> int -> float array -> int array -> int
  = "morphiq_american_residual"

let create ~lo ~diag ~hi ~rhs ~values ~payoff =
  let bands = [| lo; diag; hi; rhs; values; payoff |] in
  let n = Array.length lo in
  if n < 3 || not (Array.for_all (fun a -> Array.length a = n) bands) then
    invalid_arg "American residual band shape";
  { bands; metrics = Array.make 2 0.; indices = Array.make 3 0 }

let reset t ~obstacle =
  t.metrics.(0) <- 0.;
  t.metrics.(1) <- 0.;
  t.indices.(0) <- (if obstacle then 1 else 0);
  t.indices.(1) <- 0;
  t.indices.(2) <- 0

let run t ~first ~last = compute t.bands first last t.metrics t.indices
let visited t = t.indices.(2)
let worst t = t.metrics.(0)
let worst_row t = t.indices.(1)
let indicator t = t.metrics.(1)
