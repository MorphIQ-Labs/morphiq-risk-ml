type t = Buffer.t

let create () = Buffer.create 256

let token b s =
  Buffer.add_string b (string_of_int (String.length s));
  Buffer.add_char b ':';
  Buffer.add_string b s

let integer b n = token b (string_of_int n)
let float b x = token b (Printf.sprintf "%016Lx" (Int64.bits_of_float x))
let boolean b x = token b (if x then "true" else "false")
let contents = Buffer.contents
let digest b = Digest.BLAKE256.to_hex (Digest.BLAKE256.string (contents b))

let array f b a =
  integer b (Array.length a);
  Array.iter (f b) a

let option f b = function
  | None -> token b "none"
  | Some x ->
      token b "some";
      f b x
