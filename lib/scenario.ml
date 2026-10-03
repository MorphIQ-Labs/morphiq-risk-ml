type field = Spot | Forward | Lognormal_volatility | Normal_volatility
type adjustment = Replace of float | Add of float | Scale of float
type shock = { factor : string; field : field; adjustment : adjustment }
type point = { offset_days : int; shocks : shock list }

type range =
  | Levels of float array
  | Linear of { first : float; step : float; count : int }

let levels a =
  if Array.for_all Float.is_finite a then Ok (Levels (Array.copy a))
  else Error "nonfinite scenario level"

let range_count = function Levels a -> Array.length a | Linear r -> r.count

let range_value r i =
  if i < 0 || i >= range_count r then invalid_arg "Scenario.range_value";
  match r with
  | Levels a -> a.(i)
  | Linear r ->
      if i = 0 then r.first else Float.fma (float_of_int i) r.step r.first

let linear ~first ~step ~count =
  if
    count < 0
    || Int64.of_int count > 9007199254740992L
    || not (Float.is_finite first && Float.is_finite step)
  then Error "invalid indexed range"
  else
    let r = Linear { first; step; count } in
    if count > 0 && not (Float.is_finite (range_value r (count - 1))) then
      Error "range overflows"
    else Ok r

type mode = Absolute | Additive | Relative

type axis =
  | Market of { factor : string; field : field; mode : mode; range : range }
  | Time of int array

type specification = Paired of point array | Cartesian of axis array

type t = {
  specification : specification;
  count : int;
  bindings : (string * field) list;
}

let valid_day d = d >= 0 && d <= 1000000000
let number = function Replace x | Add x | Scale x -> x
let key (s : shock) = (s.factor, s.field)
let unique xs = List.length xs = List.length (List.sort_uniq compare xs)

let paired points =
  if
    not
      (Array.for_all
         (fun p ->
           valid_day p.offset_days
           && unique (List.map key p.shocks)
           && List.for_all
                (fun s ->
                  s.factor <> "" && Float.is_finite (number s.adjustment))
                p.shocks)
         points)
  then Error "invalid paired scenario or duplicate shock"
  else
    Ok
      {
        specification = Paired (Array.copy points);
        count = Array.length points;
        bindings =
          List.sort_uniq compare
            (Array.fold_left
               (fun acc p -> List.rev_append (List.map key p.shocks) acc)
               [] points);
      }

let axis_count = function
  | Market m -> range_count m.range
  | Time a -> Array.length a

let cartesian axes =
  let bindings =
    List.filter_map
      (function Market m -> Some (m.factor, m.field) | Time _ -> None)
      axes
  in
  let times =
    List.fold_left (fun n -> function Time _ -> n + 1 | _ -> n) 0 axes
  in
  if
    times > 1
    || (not (unique bindings))
    || List.exists
         (function
           | Time a -> not (Array.for_all valid_day a)
           | Market m -> m.factor = "")
         axes
  then Error "invalid Cartesian axes or duplicate binding"
  else
    let counts = List.map axis_count axes in
    let product =
      if List.mem 0 counts then Some 0
      else
        List.fold_left
          (fun acc n ->
            match acc with
            | Some x when n <= max_int / x -> Some (x * n)
            | _ -> None)
          (Some 1) counts
    in
    match product with
    | None -> Error "scenario count overflow"
    | Some count ->
        let axes =
          Array.of_list
            (List.map
               (function Time a -> Time (Array.copy a) | Market m -> Market m)
               axes)
        in
        Ok { specification = Cartesian axes; count; bindings }

let count t = t.count
let bindings t = t.bindings

let point t i =
  if i < 0 || i >= t.count then invalid_arg "Scenario.point";
  match t.specification with
  | Paired ps -> ps.(i)
  | Cartesian axes ->
      let index = ref i and offset_days = ref 0 and shocks = ref [] in
      for j = Array.length axes - 1 downto 0 do
        let axis = axes.(j) in
        let k = !index mod axis_count axis in
        index := !index / axis_count axis;
        match axis with
        | Time ds -> offset_days := ds.(k)
        | Market m ->
            let x = range_value m.range k in
            let adjustment =
              match m.mode with
              | Absolute -> Replace x
              | Additive -> Add x
              | Relative -> Scale x
            in
            shocks :=
              { factor = m.factor; field = m.field; adjustment } :: !shocks
      done;
      { offset_days = !offset_days; shocks = !shocks }

let apply adjustment base =
  match adjustment with
  | Replace x -> x
  | Add x -> base +. x
  | Scale x -> base *. x

let encoding t =
  let b = Buffer.create 128 in
  let token s =
    Buffer.add_string b (string_of_int (String.length s));
    Buffer.add_char b ':';
    Buffer.add_string b s
  in
  let integer n = token (string_of_int n) in
  let number x = token (Printf.sprintf "%016Lx" (Int64.bits_of_float x)) in
  let field = function
    | Spot -> token "spot"
    | Forward -> token "forward"
    | Lognormal_volatility -> token "lognormal-vol"
    | Normal_volatility -> token "normal-vol"
  in
  let range = function
    | Levels a ->
        token "levels";
        integer (Array.length a);
        Array.iter number a
    | Linear r ->
        token "linear-fma-v1";
        number r.first;
        number r.step;
        integer r.count
  in
  token "scenario-v1";
  (match t.specification with
  | Paired ps ->
      token "paired";
      integer (Array.length ps);
      Array.iter
        (fun p ->
          integer p.offset_days;
          integer (List.length p.shocks);
          List.iter
            (fun s ->
              token s.factor;
              field s.field;
              match s.adjustment with
              | Replace x ->
                  token "replace";
                  number x
              | Add x ->
                  token "add";
                  number x
              | Scale x ->
                  token "scale";
                  number x)
            p.shocks)
        ps
  | Cartesian axes ->
      token "cartesian";
      integer (Array.length axes);
      Array.iter
        (function
          | Time ds ->
              token "days";
              integer (Array.length ds);
              Array.iter integer ds
          | Market m ->
              token "market";
              token m.factor;
              field m.field;
              token
                (match m.mode with
                | Absolute -> "absolute"
                | Additive -> "additive"
                | Relative -> "relative");
              range m.range)
        axes);
  Buffer.contents b
