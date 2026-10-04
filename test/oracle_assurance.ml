let require name condition = if not condition then failwith name
let distance a b = Option.get (Float_score.distance a b)

let () =
  require "opposite signs cannot wrap"
    (Z.equal (distance 2. (-2.)) (Z.shift_left Z.one 63));
  require "opposite maximum finite"
    (Z.equal
       (distance Float.max_float (-.Float.max_float))
       (Z.of_string "18437736874454810622"));
  require "signed zeros" (Z.equal (distance 0. (-0.)) Z.zero);
  let sub = Float.succ 0. in
  require "subnormal crossing"
    (Z.equal (distance (-5. *. sub) (7. *. sub)) (Z.of_int 12));
  for exponent = -1074 to 1023 do
    let x = Float.ldexp 1. exponent in
    List.iter
      (fun y ->
        require "adjacent binade words"
          (Z.equal (distance y (Float.succ y)) Z.one))
      [ x; -.x ]
  done;
  List.iter
    (fun x ->
      require "nonfinite distance excluded" (Float_score.distance x x = None);
      require "nonfinite budget rejection"
        (not (Float_score.within ~budget:1. x x)))
    [ Float.nan; Float.infinity; Float.neg_infinity ];
  require "finite/infinity adjacency rejected"
    ((not (Float_score.within ~budget:1. Float.max_float Float.infinity))
    && not (Float_score.within ~budget:1. Float.infinity Float.max_float));
  List.iter
    (fun budget ->
      require "invalid budget" (not (Float_score.within ~budget 1. 1.)))
    [ -1.; Float.nan; Float.infinity ];
  require "fractional budget"
    (not (Float_score.within ~budget:0.5 1. (Float.succ 1.)));
  let far = Int64.float_of_bits 0x0020000000000001L in
  require "large exact distance"
    (not (Float_score.within ~budget:0x1p53 0. far));
  require "diagnostic rounds up" (Float_score.ulps 0. far = 0x1.0000000000001p53);
  let rng = Random.State.make [| 55 |] in
  let finite () =
    Int64.float_of_bits
      (Int64.logand (Random.State.bits64 rng) 0xffefffffffffffffL)
  in
  for _ = 1 to 10000 do
    let a = finite () and b = finite () and c = finite () in
    let ab = distance a b in
    require "nonnegative" (Z.sign ab >= 0);
    require "symmetric" (Z.equal ab (distance b a));
    require "identity" (Z.equal ab Z.zero = (a = b));
    require "triangle" (Z.compare ab (Z.add (distance a c) (distance c b)) <= 0)
  done;
  let data = "# witness\na 0000\nb 0001\n" in
  let expected =
    Some (2, Digest.BLAKE256.to_hex (Digest.BLAKE256.string data))
  in
  let valid x =
    Result.is_ok (Oracle_fixture.validate ~columns:[ 2 ] ~expected x)
  in
  require "complete fixture" (valid data);
  List.iter
    (fun bad -> require "corruption rejected" (not (valid bad)))
    [
      "";
      "# comment\n";
      "a 0000\n";
      data ^ "b 0001\n";
      "b 0001\na 0000\n";
      "a 0000\nb\n";
      "a 0000\nb 0002\n";
      "a 0000\na 0000\n";
    ];
  print_endline
    "oracle assurance: exact finite scoring, classifications and fixture \
     failure controls passed"
