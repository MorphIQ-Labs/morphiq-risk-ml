(** MorphIQ Risk: European option pricing, implied volatility and Greeks.

    The models are defined in docs/model-contracts.md, and every served
    quantity is measured against those definitions (docs/results-slice.md).
    The stability policy (docs/stability.md) covers everything here except
    {!Internal}.

    {1 Use}

    {[
      let a = Black.Bsm.admit { spot = 100.; strike = 95.; time_to_expiry = 0.5; rate = 0.03; dividend_yield = 0.01 } in
      match a, Vol.lognormal 0.2 with
      | Ok a, Ok sigma -> Black.Bsm.price a Side.Call sigma
      | Error e, _ | _, Error e -> failwith (Refusal.to_string e)
    ]} *)

val version : string
(** The library's semantic version. *)

module Side = Side
module Refusal = Refusal
module Vol = Vol
module Units = Units
module Iv = Iv
module Greeks = Greeks
module Black = Black
module Bachelier = Bachelier
module Normal = Normal

(** Numerical building blocks, exposed for testing and research. They are
    not covered by the stability policy and may change in any release. *)
module Internal : sig
  module Elementary = Elementary
  module Cody = Cody
  module Split = Split
  module Dd = Dd
  module Normal_dd = Normal_dd
  module Normalised_black = Normalised_black
  module Lbr = Lbr
end
