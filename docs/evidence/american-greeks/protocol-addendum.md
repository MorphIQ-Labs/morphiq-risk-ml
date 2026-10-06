# Pre-qualification derivation corrections

The first canonical spatial run exposed QuantLib's `Null<Real>()` theta sentinel
as a finite binary64 number. Retain that raw attempt; the corrected adapter
records it as unavailable. Its event list contains time zero, which prevents
QuantLib's snapshot theta. Numerical theta therefore needs the independent
fixed-event quadrature roll, not that sentinel or a claim of canonical agreement.

A central derivative can converge to the average of two unequal one-sided
slopes at a kink. In addition to the frozen mesh/bump checks, require the
fine-bump right-minus-left slope difference to fit the existing target/8 stencil
budget. This is a stricter necessary smoothness screen, not a proof of
existence. No numerical target is widened. Keep both sides and the base price
on the same analytical/numerical route; otherwise report unavailable. This
correction follows the derivative definition, before reference scoring.

Whole-request bounds partition numerical work over one base solve, six solves
per requested parallel derivative, and one derivative-preparation share. Reserve
64 KiB plus bounded coefficient-copy storage in addition to the price solver's
workspace. Unused partitions do not expand a later solve's budget. This is a
conservative finite-work policy, not a workload capacity claim.
