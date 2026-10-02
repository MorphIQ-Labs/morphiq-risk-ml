(* Double-double log, exp and expm1 against mpmath at 60 digits (pinned).
   Each must hold 2^-100 relative, except exp's reduction error, |x| 2^-105,
   and a value near the bottom of the range, whose low part underflows
   (2^-50). *)
open Morphiq_risk.Internal

let logs = [
  (0x1.0000000000000p+0, 0x0.0p+0, 0x0.0p+0);
  (0x1.0400000000000p+0, 0x1.fc0a8b0fc03e4p-7, -0x1.83092c59642a1p-62);
  (0x1.8000000000000p+0, 0x1.9f323ecbf984cp-2, -0x1.a92e513217f5cp-59);
  (0x1.fffffffffffffp+0, 0x1.62e42fefa39eep-1, 0x1.abc9e3b39803dp-56);
  (0x1.6a09e667f3bcdp+0, 0x1.62e42fefa39f0p-2, 0x1.c2e0e1b1548c2p-56);
  (0x1.f5dc99badec5bp-1, -0x1.47ae147ae1489p-6, -0x1.d8c534bdbfaa3p-60);
  (0x1.56e1fc2f8f359p-997, -0x1.5963447f87fb5p+9, -0x1.aa670d35324e6p-46);
  (0x0.0000000000001p-1022, -0x1.74385446d71c3p+9, -0x1.8e569fa8ee781p-45);
  (0x1.e42d130773b76p+1023, 0x1.62dd08fdc6f88p+9, 0x1.16a687db2877dp-45);
  (0x1.5bf0a8b145769p+1, 0x1.0000000000000p+0, -0x1.ea8556644e4cdp-55);
  (0x1.b7cdfd9d7bdbbp-34, -0x1.7069e2aa2aa5bp+4, 0x1.f0b709e89338fp-52);
  (0x1.e06689845aa7fp-1, -0x1.04eeece099b03p-4, 0x1.df252242e7301p-58);
  (0x1.286ad49b86638p+0, 0x1.2c37d10bc62b9p-3, 0x1.c207b417312c6p-57);
  (0x1.f4893b875b9e5p+0, 0x1.574c10c558952p-1, -0x1.72bdd5dedbd4dp-55);
  (0x1.d6e42fbe71bd9p-1, -0x1.56d2e7fcb39afp-4, -0x1.79f7626cec0c5p-61);
  (0x1.429acfdcb0dfdp-1, -0x1.d8fb7879d0ceap-2, -0x1.274cca17e6749p-58);
  (0x1.928b19ca4f9bap+0, 0x1.cf7d06ffa257cp-2, -0x1.a551d15474e3dp-57);
  (0x1.ee5a0f0b1920ap-1, -0x1.1f5a49591c523p-5, -0x1.12a8f4d35c88fp-60);
  (0x1.832afe820ce12p+0, 0x1.a79c063f482a4p-2, -0x1.2fb5ca9832384p-59);
  (0x1.a7df67a753a87p-1, -0x1.82d98d2717647p-3, 0x1.63d247b478d56p-58);
  (0x1.5d85851668540p-1, -0x1.86ebedbc8b17ap-2, 0x1.a100448fcf4d5p-56);
  (0x1.9ee769366ce8ep+0, 0x1.ee755e6511da6p-2, -0x1.fb64ca763fed0p-57);
  (0x1.1556b8264ac53p-1, -0x1.39e6454e2d74dp-1, -0x1.64bd13ce98e20p-55);
  (0x1.0c01459ac7594p+0, 0x1.776c701ac486fp-5, -0x1.b00bced191dbcp-60);
  (0x1.b63dd3fb84554p-1, -0x1.3e935647db4a9p-3, -0x1.f37ba09a4c0dfp-57);
  (0x1.ff4659e59f052p+0, 0x1.622a6824be1cep-1, -0x1.d0ebccf7e8421p-57);
  (0x1.2e0047127eddep-1, -0x1.0e481fe2deeb0p-1, 0x1.e744b5d4d7e08p-57);
  (0x1.47e9b27514d36p-1, -0x1.c8453fbc59a05p-2, 0x1.4684e57912780p-56);
  (0x1.bb39e2d967bcdp+0, 0x1.1909c39ae0a0dp-1, -0x1.c2927deab96b7p-55);
  (0x1.dedcb11d2cd3cp-1, -0x1.12125338a30c0p-4, 0x1.2f23c9dcc2c0cp-58);
  (0x1.7caa62f378c80p+0, 0x1.96440088fee76p-2, 0x1.b2400118b84bfp-58);
  (0x1.84aedf785e657p-13, -0x1.12fc87bade500p+3, 0x1.b2211e56f2099p-62);
  (0x1.8fb8337604fd5p+985, 0x1.5599080ffc770p+9, 0x1.b13d7faa70748p-55);
  (0x1.80126243613a2p-893, -0x1.35499265465cdp+9, -0x1.5f30983fe8322p-56);
  (0x1.919362c3f0489p+603, 0x1.a26afffcbea44p+8, 0x1.2e02e4fee7e66p-55);
  (0x1.7fe38da300cedp-853, -0x1.276cb82253d03p+9, 0x1.338d36c6b4bfcp-58);
  (0x1.6dc201c190722p-20, -0x1.b032609bfaa00p+3, -0x1.5ed7d3c8212e2p-54);
  (0x1.b090dd986172dp-346, -0x1.de9bd60717ac6p+7, -0x1.fa74c8b2b5c84p-59);
  (0x1.6bd20a07e4424p+158, 0x1.b7799659aebc0p+6, -0x1.0aa7b541b4da5p-54);
  (0x1.b020ad821549dp+218, 0x1.2f425eb989e0cp+7, 0x1.483d3847a9456p-55);
  (0x1.4da26b42db4ddp-369, -0x1.ff034c40d429ap+7, 0x1.657e73bb8e3fdp-54);
  (0x1.a6a79e4c53c0cp-304, -0x1.a46e4446dfbfep+7, 0x1.a19abe802e964p-58);
  (0x1.88fe8961c8cdap-905, -0x1.396f4e6c536f4p+9, 0x1.f91d26b0ff209p-55);
  (0x1.d762f2b1b2631p+476, 0x1.4a8c6e5af147cp+8, -0x1.7122ee82105f4p-55);
  (0x1.4f4382101c8b9p+333, 0x1.ce2cedb597488p+7, 0x1.71d2741938549p-54);
  (0x1.382cf616d349fp-417, -0x1.20d80f73ee18dp+8, 0x1.72030f606259ap-56);
  (0x1.b427365349d1fp+810, 0x1.18fdb33c0b278p+9, 0x1.c463fc6eb50e6p-56);
  (0x1.6253ea7916c37p+588, 0x1.97e54533b497cp+8, -0x1.5ccd6e65ffaacp-65);
  (0x1.8393ae3c1645bp-667, -0x1.cdea18422e720p+8, 0x1.de6b0cdb8511dp-61);
  (0x1.97d39432023ddp-460, -0x1.3e61cd49fe81ap+8, -0x1.dd98b7a98b488p-58);
  (0x1.0f2b5882dd7e2p-999, -0x1.5a32bf71a20f0p+9, 0x1.17e61d1867d55p-55);
]

let exps = [
  (0x0.0p+0, (0x1.0000000000000p+0, 0x0.0p+0), (0x0.0p+0, 0x0.0p+0));
  (0x1.79ca10c924223p-67, (0x1.0000000000000p+0, 0x1.79ca10c924223p-67), (0x1.79ca10c924223p-67, 0x1.16c262777579cp-134));
  (-0x1.19799812dea11p-40, (0x1.fffffffffdcd1p-1, -0x1.9812de0651eb3p-56), (-0x1.19799812de065p-40, -0x1.eb32bbc37d24ap-96));
  (0x1.61e4f765fd8aep-8, (0x1.0162da04e41a9p+0, -0x1.4d19baaf9d3ecp-54), (0x1.62da04e41a8adp-8, -0x1.19baaf9d3ebeap-62));
  (-0x1.61e4f765fd8aep-8, (0x1.fd3e1e6951bebp-1, -0x1.3587b5d2451a9p-56), (-0x1.60f0cb5720a93p-8, -0x1.61ed749146a60p-62));
  (0x1.89374bc6a7efap-8, (0x1.018a65e409d1dp+0, -0x1.0e491f26a5e5cp-54), (0x1.8a65e409d1cbcp-8, 0x1.b6e0d95a1a428p-62));
  (0x1.6666666666666p-2, (0x1.6b4802c805decp+0, 0x1.b4d745fdfd640p-54), (0x1.ad200b20177b2p-2, -0x1.2ca2e8080a702p-56));
  (-0x1.6666666666666p-2, (0x1.68cce09671f71p-1, 0x1.7fb15788d6630p-57), (-0x1.2e663ed31c11ep-2, 0x1.7fb15788d6630p-57));
  (0x1.0000000000000p+0, (0x1.5bf0a8b145769p+1, 0x1.4d57ee2b1013ap-53), (0x1.b7e151628aed3p+0, -0x1.655023a9dfd8cp-54));
  (-0x1.4000000000000p+1, (0x1.50385c094f425p-4, -0x1.6286df2d50a3fp-58), (-0x1.d5f8f47ed617bp-1, -0x1.ac50dbe5aa148p-55));
  (0x1.e000000000000p+4, (0x1.370470aec28edp+43, -0x1.85e0eff0462d6p-11), (0x1.370470aec26edp+43, -0x1.85e0eff0462d6p-11));
  (0x1.5e00000000000p+9, (0x1.d945df4f8ec8ep+1009, 0x1.183392684a46ep+954), (0x1.d945df4f8ec8ep+1009, 0x1.183392684a46ep+954));
  (-0x1.5e00000000000p+9, (0x1.14f2b0fb9307fp-1010, 0x0.00000000000acp-1022), (-0x1.0000000000000p+0, 0x0.0p+0));
  (-0x1.7400000000000p+9, (0x0.0000000000002p-1022, -0x0.0p+0), (-0x1.0000000000000p+0, 0x0.0p+0));
  (0x1.6280000000000p+9, (0x1.d422d2be5dc9bp+1022, -0x1.916aa7a2c8d07p+967), (0x1.d422d2be5dc9bp+1022, -0x1.916aa7a2c8d07p+967));
  (0x1.bd28baf565ed0p+4, (0x1.19f38466613f3p+40, -0x1.c9f6c82eac0b4p-16), (0x1.19f38466603f3p+40, -0x1.c9f6c82eac0b4p-16));
  (-0x1.82109c3b19835p+5, (0x1.4cbe234b8b21ep-70, -0x1.8a55f940ca64cp-124), (-0x1.0000000000000p+0, 0x1.4cbe234b8b21ep-70));
  (-0x1.cbb38f4262300p+2, (0x1.8e33f94834fd9p-11, 0x1.ac7a361748b31p-65), (-0x1.ff9c7301adf2cp-1, -0x1.34a70b93d16eap-58));
  (-0x1.7a34ee90f2a32p+5, (0x1.bc4b593d5007bp-69, 0x1.00ad37ff9ea24p-125), (-0x1.0000000000000p+0, 0x1.bc4b593d5007bp-69));
  (0x1.0d3fa853b81c0p+1, (0x1.063c2971332bbp+3, -0x1.494e388af7437p-53), (0x1.cc7852e266576p+2, -0x1.494e388af7437p-53));
  (0x1.a9f77d9490bc0p+4, (0x1.53d9d68c8db3bp+38, -0x1.930d4b566d991p-16), (0x1.53d9d68c89b3bp+38, -0x1.930d4b566d991p-16));
  (-0x1.4d973964f08b2p+5, (0x1.caa9b3db0da68p-61, 0x1.205f74d3733d4p-117), (-0x1.0000000000000p+0, 0x1.caa9b3db0da68p-61));
  (0x1.ee806213d2ac8p+4, (0x1.80ec751ab58bcp+44, -0x1.2ccde78966cb6p-11), (0x1.80ec751ab57bcp+44, -0x1.2ccde78966cb6p-11));
  (-0x1.6e0c84e59b23ep+5, (0x1.fbb7be9345e9dp-67, -0x1.adf7212fcadbdp-121), (-0x1.0000000000000p+0, 0x1.fbb7be9345e9dp-67));
  (-0x1.b3bbe60e89508p+2, (0x1.218b28272a2d3p-10, 0x1.b3a69d126eacdp-64), (-0x1.ff6f3a6bec6afp-1, 0x1.a6d9d34e89375p-55));
  (0x1.8eaa086458d14p+4, (0x1.ed81eacf242f6p+35, -0x1.c7063ee9fd09fp-19), (0x1.ed81eacf042f6p+35, -0x1.c7063ee9fd09fp-19));
  (0x1.39262da83a6b8p+4, (0x1.2d884771aef29p+28, 0x1.e5080ea001c82p-30), (0x1.2d884761aef29p+28, 0x1.e5080ea001c82p-30));
  (-0x1.95263aa92a4b0p+2, (0x1.d2ef76ae08666p-10, 0x1.717cdc360e1afp-65), (-0x1.ff168844a8fbdp-1, 0x1.98b8be6e1b071p-56));
  (0x1.a8579e96b9c64p+4, (0x1.330a15bf0430dp+38, 0x1.1bf0f23befbf4p-16), (0x1.330a15bf0030dp+38, 0x1.1bf0f23befbf4p-16));
  (-0x1.41c82ee5d61acp+4, (0x1.fada3cab71b8cp-30, -0x1.cb193de4db2b1p-84), (-0x1.fffffff0292e2p-1, 0x1.56e37171a7361p-55));
  (0x1.2ee0e95be7d08p+5, (0x1.897cd9701163bp+54, -0x1.21530cfeffa47p-2), (0x1.897cd9701163bp+54, -0x1.4854c33fbfe92p+0));
  (-0x1.336556b29a798p+5, (0x1.7ac5f4d97d82ap-56, 0x1.46577548f356ap-110), (-0x1.0000000000000p+0, 0x1.7ac5f4d97d82ap-56));
  (0x1.ac40b30003dc0p+4, (0x1.880be3343cf63p+38, 0x1.fc97cf9921a52p-18), (0x1.880be33438f63p+38, 0x1.fc97cf9921a52p-18));
  (-0x1.b6bc43ffe69f0p+3, (0x1.2a29a8b0dbfe8p-20, 0x1.bd0b8fc65d30ap-74), (-0x1.ffffdabacae9ep-1, -0x1.200bc85e8e073p-55));
  (-0x1.9ef620b3584bap+4, (0x1.7fa1797537de1p-38, 0x1.cb3d2420e8e59p-92), (-0x1.fffffffff402fp-1, -0x1.0d159043d1a61p-55));
  (0x1.6813059e5cb9cp-8, (0x1.016910b742939p+0, -0x1.ba8bd59180d3bp-55), (0x1.6910b742938c9p-8, -0x1.45eac8c069dbcp-62));
  (0x1.6be51b1f4b96cp-9, (0x1.00b6334554d12p+0, -0x1.e1c3bbf1562ddp-56), (0x1.6c668aa9a23c4p-9, -0x1.c3bbf1562dccbp-64));
  (-0x1.6aa0ac8ecdc80p-11, (0x1.ffa55fdb0e406p-1, -0x1.490580f3d3eefp-59), (-0x1.6a8093c6fe815p-11, 0x1.be9fc30b04434p-65));
  (-0x1.30834cf89ffcfp-8, (0x1.fda0630eb4c4ep-1, 0x1.0039cc95932b7p-55), (-0x1.2fce78a59d8e0p-8, 0x1.ce64ac995bbb4p-66));
  (-0x1.de26a00b51a9cp-8, (0x1.fc472da929ea1p-1, -0x1.86722c8281c54p-57), (-0x1.dc692b6b0af8cp-8, -0x1.9c8b20a07151ep-63));
  (0x1.2928070b920cbp-7, (0x1.02550400f2a96p+0, -0x1.fb3874659d1e6p-55), (0x1.2a82007954ae0p-7, 0x1.31e2e698b8686p-61));
  (-0x1.4db54bb999d08p-8, (0x1.fd6647aced8a3p-1, -0x1.53cdf6c2b6f18p-56), (-0x1.4cdc29893ae95p-8, -0x1.e6fb615b78bdap-63));
  (0x1.26c102d092e60p-10, (0x1.0049badcb7d76p+0, -0x1.2e7a5e7f5fd88p-54), (0x1.26eb72df5d6d2p-10, -0x1.e979fd7f62095p-64));
  (-0x1.3292ca3cc1748p-8, (0x1.fd9c48fc63c04p-1, -0x1.98d8437661cc2p-56), (-0x1.31db81ce1fe1ap-8, 0x1.c9ef22678cf82p-62));
  (-0x1.5b2bd0937fba0p-11, (0x1.ffa93c66aff64p-1, 0x1.cdebd6f006d67p-55), (-0x1.5b0e654026e32p-11, -0x1.4290ff9298f9cp-67));
  (0x1.3478919b94412p-8, (0x1.013532b583448p+0, 0x1.2f6073e57934dp-54), (0x1.3532b5834484cp-8, -0x1.3f18350d965f9p-63));
  (-0x1.5e4f10e509bdap-8, (0x1.fd45406024844p-1, 0x1.5fcec094eea3ep-55), (-0x1.5d5fcfedbddd4p-8, -0x1.89fb588ae1226p-66));
  (0x1.c2a388887bdeap-8, (0x1.01c4311354757p+0, 0x1.d6800f844963ep-55), (0x1.c43113547573bp-8, -0x1.7ff07bb69c259p-63));
  (0x1.0bb3dd7a8d761p-7, (0x1.021999236f30cp+0, -0x1.3ae5498de2290p-54), (0x1.0ccc91b7985d9p-7, -0x1.72a4c6f1147f2p-61));
  (0x1.5032fc5a3c5a0p-11, (0x1.002a09d2c75cbp+0, -0x1.eb725769044cdp-54), (0x1.504e963ae5429p-11, 0x1.b512df7666679p-67));
  (-0x1.fb91d646418f6p-9, (0x1.fe05696d69a3cp-1, 0x1.a5b42bb8b210fp-57), (-0x1.fa9692965c3e6p-9, 0x1.6d0aee2c843bfp-63));
  (-0x1.2d1ef2540fb9bp-7, (0x1.fb5108a9640aep-1, 0x1.72a7c1a17bc43p-58), (-0x1.2bbdd5a6fd47dp-7, -0x1.ab07cbd0877aep-63));
  (-0x1.1c69dd6683d8ap-8, (0x1.fdc867cb5e0efp-1, -0x1.2939d3ec01f60p-56), (-0x1.1bcc1a50f8893p-8, 0x1.b18b04ff8280ap-62));
  (0x1.4778cd7396da0p-12, (0x1.0014785e4fb96p+0, 0x1.dda16bab53963p-54), (0x1.4785e4fb96777p-12, -0x1.e9454ac69cc39p-66));
  (-0x1.2e37e5a5c43eap-7, (0x1.fb4caf2887763p-1, -0x1.8134377936112p-56), (-0x1.2cd435de2274cp-7, -0x1.343779361124cp-64));
]

let rel (got : Dd.t) (hi, lo) =
  if hi = 0.0 then Float.abs got.hi else Float.abs (Dd.to_float (Dd.sub got { Dd.hi; lo }) /. hi)

(* The low part of a value near the bottom of the range underflows: there the
   double-double carries fewer bits. *)
let budget hi = if Float.abs hi < 0x1p-960 then 0x1p-50 else 0x1p-100

(* exp reduces r = x - m ln 2 with ln 2 to 106 bits; m ln 2's rounding,
   about |x| 2^-105 absolute in r, is relative error in e^x. *)
let exp_budget x hi = budget hi +. (Float.abs x *. 0x1p-105)

let () =
  let worst = Hashtbl.create 3 and failures = ref [] in
  let check ?budget:b what x got want =
    let e = rel got want in
    Hashtbl.replace worst what (Float.max e (Option.value ~default:0.0 (Hashtbl.find_opt worst what)));
    if e > Option.value b ~default:(budget (fst want)) then failures := Printf.sprintf "%s(%h): %.2e relative" what x e :: !failures
  in
  List.iter (fun (a, h, l) -> check "log" a (Dd.log_float a) (h, l)) logs;
  List.iter
    (fun (x, e, m) ->
      check ~budget:(exp_budget x (fst e)) "exp" x (Dd.exp (Dd.of_float x)) e;
      check ~budget:(exp_budget x (fst m)) "expm1" x (Dd.expm1 (Dd.of_float x)) m)
    exps;
  Hashtbl.iter (fun what w -> Printf.printf "double-double %s: worst %.2e relative\n" what w) worst;
  List.iter print_endline !failures;
  if !failures <> [] then exit 1

