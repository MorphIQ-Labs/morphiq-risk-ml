# Frozen #116 certification experiment

Base: integration `03d8920ddffa7c5456b7fc2280348e5f04cda7f6`. Fix this protocol
before implementing or scoring the new API. This is a supported-subset gate,
not a claim that the PDE solver has a continuum certificate.

Evaluate three exact-model reductions for admitted constant-coefficient inputs
without a cash specification: expiry; terminal-only American/Bermudan exercise;
and calls with q=0 and r>=0. Terminal exercise is mandatory under admission.
All other stopping/cash/piecewise capabilities remain estimated-only. Do not
silently ignore a zero-payment event or transfer a price certificate to Greeks
or inverse roots. The production owner must preserve original spot/strike,
rate/yield, horizon and volatility words in its existing European enclosure.

Expose the reductions separately from estimated pricing, with an abstract
validated absolute currency-error limit, private finite certificate and explicit
unsupported/arithmetic/accuracy/cancellation failures. No PDE refinement or
residual enters the accepted error. Invalid accuracy is not unsupported pricing.
Zero requested error succeeds only for an exact certificate. No global cache,
new runtime dependency or general American Production dispatcher is required.

Before candidate scores, retain the exact corpus and independent Arb endpoint
references. Exercise S=80/100/120, K=100, rates=-.05/0/.05, volatility=0/.2/.8,
terminal-only q=-.03/.02 calls and puts; q=0 eligible calls include American
windows opening at 0/.5 and finite rights. Add expiry exact/inexact/subnormal
payoffs, zero spot/strike, scale extremes, tiny horizons, negative-zero guards,
negative-rate/yield guard neighbors, finite unresolvable discount exponents,
cash/zero-cash, nonterminal puts, invalid limits and cancellation.
The ordinary requested limit is 2^-36*max(S,K), with the smallest subnormal
floor. This is a test input, not a business tolerance. Every successful
certificate must contain the entire independently enclosed reference interval
using exact rational comparisons; no ULP slack or subtraction of reference
uncertainty. Retain unsupported and unresolved rows. A reference too wide to
score is unresolved, never passed. Refine Arb from 256 to 512/1024/2048 bits;
record endpoints, source/tool versions and failed precision attempts.

Execute explicit general-stopping feasibility probes: coarse full-domain cap
width, an exactly solved discrete system versus continuum error, and a payoff
supersolution candidate whose unverified convex join defeats off-kink PDE
checks. Document the required missing space/time, exterior, cash mapping,
coefficient and global residual obligations. No finite experiment establishes
that a stronger proof is impossible. Do not call a smooth-patch residual bound
a global supersolution certificate.

Require native/bytecode and installed-client checks, development/release suites,
private-type rejection, compiled incorrect-guard/bound faults and collector
failure controls. Retain original pricing behavior; this is an additive API.
Measure the new call separately from admission after owned validation exits,
with source/binary identity, five processes, warmup, allocation and host load.
No speed target is assigned to this new capability. Default PR CI remains five
jobs/seven core mutants; final source-artifact/institutional review stays #120.
