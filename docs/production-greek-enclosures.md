# Smooth Greek runtime enclosures

The production adapter evaluates the exact real models with outward arithmetic
and analytical normal/exponential enclosures. This derivation precedes scoring.
It covers T>0 and sigma>0. Expiry and zero-volatility Greeks are explicitly
unsupported by this initial adapter; their fast-API semantics remain separate.
No measured region budget enters a successful production certificate.

Write theta=+1 for a call, -1 for a put, phi=standard normal density and
Phi=its CDF. All inputs, shifted sums and constants below are exact real
quantities enclosed by the runtime arithmetic. Time outputs divide the stated
annual expression by the exact integer 365. This is negative maturity
sensitivity, not a calendar/date-roll implementation.

## Black family

Let A=S exp(-qT), C=K exp(-rT), x=log(S/K)+(r-q)T, s=sigma sqrt(T),
d1=x/s+s/2, d2=d1-s and P=A phi(d1). For displaced Black, S and K are the
exact shifted sums. Holding all other independent model inputs fixed gives

    w = partial(d1)/partial(T)
      = [2(r-q)T-x]/(2Ts) + sigma/(4 sqrt(T)).

Differentiate the model price, using A phi(d1)=C phi(d2),
phi'(z)=-z phi(z), d1_S=1/(Ss), and
partial(d1)/partial(sigma)=-d2/sigma. The sensitivities are

| Quantity | Exact expression |
| --- | --- |
| delta | theta (A/S) Phi(theta d1) |
| gamma | P/(S²s) |
| annual theta | theta[q A Phi(theta d1)-r C Phi(theta d2)]-P sigma/(2 sqrt(T)) |
| vega | P sqrt(T) |
| BSM rho | theta T C Phi(theta d2) |
| fixed-forward rho | -T V |
| vanna | -(P/S) d2/sigma |
| volga | vega d1 d2/sigma |
| annual charm | q delta-(P/S) w |
| annual veta | vega [q+d1 w-1/(2T)] |
| annual color | gamma [q+d1 w+1/(2T)] |

BSM rho holds q fixed, including when the supplied q equals r. The forward
models vary q and r together. The model-specific production owner supplies
this distinction; numeric equality of rates cannot infer it.

## Bachelier

Let D=exp(-rT), s=sigma sqrt(T), d=(F-K)/s and P=D phi(d).
Here d_F=1/s, d_sigma=-d/sigma and d_T=-d/(2T). Differentiation gives

| Quantity | Exact expression |
| --- | --- |
| delta | theta D Phi(theta d) |
| gamma | P/s |
| annual theta | r V-P sigma/(2 sqrt(T)) |
| vega | P sqrt(T) |
| rho | -T V |
| vanna | -P d/sigma |
| volga | vega d²/sigma |
| annual charm | r delta+P d/(2T) |
| annual veta | vega [r-(1+d²)/(2T)] |
| annual color | gamma [r+(1-d²)/(2T)] |

## Error and capability contract

Each expression is evaluated with the existing enclosure operations. This
propagates input-transformation, finite arithmetic, analytical truncation and
underflow allowances, including cancellations in the time brackets. The
[normal bounds](model-enclosures.md) remain valid after multiplication by any
enclosed prefactor; a small unweighted tail does not imply a small weighted
error. If the final radius is too large, the request fails its accuracy limit.
An overflowing intermediate or unresolved denominator is an explicit numerical
failure, even where another algorithm could evaluate the real quantity.

A returned expansion contains the real quantity in the sum of its words plus
or minus its nonnegative radius. Choose its finite leading word v as the
served float. `error_of_float` bounds the absolute real error |v-Q|, including
all other words and the radius. The production adapter accepts only a finite
bound no greater than the caller's finite, nonnegative, typed absolute limit.
Thus exact zeros and subnormals use the same absolute criterion; neither a
relative-error division nor an empirical ULP escape is needed. This does not
promise that every mathematically admitted request succeeds.

Independent references must cover all ten derivatives and both rho conventions,
including exact displaced sums, cancellations and tails. Tests exercise
admission, capability and numerical-accuracy failures as outcomes, and enforce
unit/model distinctions at compile time. Bounds are derived before those tests;
failures do not authorize widening the requested limit.

## Call-local reuse

The multi-output owner may reuse an identical enclosure for fixed model, side,
volatility and rho convention. [Shared Greek intermediates](shared-greek-intermediates.md)
retain the operation graph and arithmetic preconditions above. Quantity-specific
expressions are lazy so that a failure cannot suppress an independent derivative.
Each final result still gets its own outward error calculation and typed limit.
No error allowance changes; the same references and mutation witnesses apply.
