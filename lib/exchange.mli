(** Certified scalar European exchange prices. Receive one unit of one asset
    against delivery of one unit of another, in the same currency. Original
    binary64 inputs denote exact reals; common interest rate cancels. *)

type leg = Receive | Deliver
type field = Spot | Dividend_yield

type input_error =
  | Invalid_asset of leg * field
  | Invalid_time
  | Invalid_correlation

type correlation
(** Finite correlation in the closed interval [-1,1]. *)

val correlation : float -> (correlation, input_error) result

type asset = {
  spot : float;
  dividend_yield : float;
  volatility : Vol.lognormal Vol.t;
}

type admitted

val admit :
  receive:asset ->
  deliver:asset ->
  time_to_expiry:float ->
  correlation:correlation ->
  (admitted, input_error) result
(** Validate both legs and maturity before selecting any boundary. Spots and
    maturity must be finite and nonnegative; yields must be finite. Reverse
    exchange swaps the complete asset records. Admission does not guarantee
    numerical availability. *)

type error = Invalid_accuracy | Numerical_failure | Accuracy_exceeded

type certified_price = private { value : float; absolute_error : float }
(** Finite currency value and finite nonnegative outward absolute error for the
    exact model price. Includes arithmetic uncertainty, not model or market data
    uncertainty. *)

val price : admitted -> max_error:float -> (certified_price, error) result
(** Require a finite nonnegative currency limit. Zero limit requires an exact
    certificate. Expiry and zero variance have defined positive-part prices.
    Unresolved arithmetic has no fallback value. This initial capability uses
    bounded scalar enclosures, including |q*T| <=256 for required discounts. See
    docs/first-model-extension.md and the implementation method/evidence.
    Greeks, inverse parameters and portfolio adapters are outside this API. *)
