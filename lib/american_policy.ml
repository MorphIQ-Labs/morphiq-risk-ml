type phase = Select | Eliminate | Substitute | Copy

type t = {
  bands : float array array;
  flags : bool array array;
  state : int array;
}

external compute :
  float array array -> bool array array -> int array -> int -> int -> int
  = "morphiq_american_policy"

let create ~lo ~diag ~hi ~rhs ~values ~payoff ~pivots ~solution_rhs ~candidate
    ~mask ~oldmask =
  let bands =
    [| lo; diag; hi; rhs; values; payoff; pivots; solution_rhs; candidate |]
  in
  let n = Array.length lo in
  if
    n < 3
    || (not (Array.for_all (fun a -> Array.length a = n) bands))
    || Array.length mask <> n
    || Array.length oldmask <> n
    || mask == oldmask
  then invalid_arg "American policy band shape or alias";
  Array.iteri
    (fun i a ->
      for j = 0 to i - 1 do
        if a == bands.(j) then invalid_arg "American policy band alias"
      done)
    bands;
  { bands; flags = [| mask; oldmask |]; state = [| 0; 0; 0; 17; 0 |] }

let reset t ~obstacle =
  t.state.(1) <- (if obstacle then 1 else 0);
  t.state.(2) <- 0;
  t.state.(3) <- 17;
  t.state.(4) <- 0

let run t phase ~first ~last =
  t.state.(0) <-
    (match phase with
    | Select -> 0
    | Eliminate -> 1
    | Substitute -> 2
    | Copy -> 3);
  compute t.bands t.flags t.state first last

let changed t = t.state.(2) = 1
let fingerprint t = t.state.(3)
let visited t = t.state.(4)
