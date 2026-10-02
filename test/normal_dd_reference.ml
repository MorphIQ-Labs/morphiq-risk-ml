(* Independent pinned values, with the analytical Normal_dd majorants from
   the series derivation. The generated DD corpus additionally tests both
   input words at thousands of normal arguments. *)
open Morphiq_risk

let cases =
  [
    ( -0x1.8000000000000p+2,
      (0x1.0f30ef0092d48p-30, 0x1.f0faa93e340a9p-85),
      (0x1.a1880fbd087fcp-28, 0x1.18d15a785658cp-82) );
    ( -0x1.6000000000000p+2,
      (0x1.463cfa9c7fce7p-26, 0x1.d319482f286c1p-80),
      (0x1.ce8ec39250975p-24, 0x1.b565716c2634ap-79) );
    ( -0x1.8000000000000p+1,
      (0x1.61de1f985b5d7p-10, -0x1.dd537b698460ep-65),
      (0x1.227213fd77689p-8, -0x1.9f32adc08250fp-62) );
    ( -0x1.0000000000000p+0,
      (0x1.44ed0bb7cb20bp-3, 0x1.6d0374584348cp-58),
      (0x1.ef8e58e331737p-3, 0x1.c30e33c93dc5ep-57) );
    ( -0x1.999999999999ap-4,
      (0x1.d7375f15b2f1ep-2, 0x1.389de104a8fd7p-58),
      (0x1.967aba85e91ddp-2, 0x1.dd4f9954cf89cp-57) );
    ( -0x1.5798ee2308c3ap-27,
      (0x1.ffffffbb76554p-2, -0x1.b6f2304faec55p-57),
      (0x1.9884533d43650p-2, 0x1.88932f8daec5cp-57) );
    ( 0x0.0p+0,
      (0x1.0000000000000p-1, 0x0.0p+0),
      (0x1.9884533d43651p-2, -0x1.cbc0d30ebfd15p-56) );
    ( 0x1.5798ee2308c3ap-27,
      (0x1.0000002244d56p-1, 0x1.b6f2304faec55p-57),
      (0x1.9884533d43650p-2, 0x1.88932f8daec5cp-57) );
    ( 0x1.3333333333333p-2,
      (0x1.3c5ee2cc40b79p-1, -0x1.80d191d6ee216p-55),
      (0x1.868a8709fbbbfp-2, 0x1.5783f765b7e00p-58) );
    ( 0x1.0000000000000p+0,
      (0x1.aec4bd120d37dp-1, 0x1.a4bf22e9ef2ddp-56),
      (0x1.ef8e58e331737p-3, 0x1.c30e33c93dc5ep-57) );
    ( 0x1.4000000000000p+1,
      (0x1.fcd21635036c6p-1, 0x1.ba6abef31e8c8p-56),
      (0x1.1f2f0557f5256p-6, 0x1.24a8e793d0774p-61) );
    ( 0x1.0000000000000p+2,
      (0x1.fffbd94a1aad4p-1, 0x1.0e83426c70d94p-64),
      (0x1.18a98e2c0b4b4p-13, 0x1.a89982a93fe63p-67) );
    ( 0x1.8000000000000p+2,
      (0x1.fffffff786788p-1, 0x1.feda56f83c156p-55),
      (0x1.a1880fbd087fcp-28, 0x1.18d15a785658cp-82) );
  ]

let rel (got : Internal.Dd.t) (hi, lo) =
  let num = Internal.Dd.sub got { Internal.Dd.hi; lo } in
  Float.abs (Internal.Dd.to_float num /. hi)

let () =
  let failures =
    List.filter_map
      (fun (d, cdf, pdf) ->
        let x = Internal.Dd.of_float d in
        let ec = rel (Internal.Normal_dd.cdf x) cdf
        and ep = rel (Internal.Normal_dd.pdf x) pdf in
        let cdf_budget = Bounds.normal_cdf_absolute /. fst cdf in
        if
          not
            (Float.is_finite ec && Float.is_finite ep && ec <= cdf_budget
            && ep <= Bounds.normal_pdf_relative)
        then Some (Printf.sprintf "d=%h cdf %.1e pdf %.1e" d ec ep)
        else None)
      cases
  in
  List.iter print_endline failures;
  if failures <> [] then exit 1
  else print_endline "normal_dd: all cases within budget"
