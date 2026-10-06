# Supplementary canonical comparison

The frozen quadrature route leaves many derivatives unresolved at its selected
resolutions. Keep those outcomes and their uncertainty. Add an independent
QuantLib comparison for all five quantities using its log-grid spline delta/
gamma and the same parallel bumps/fixed-future-event valuation rolls. This does
not replace an unresolved quadrature reference or imply certified accuracy.
Use the already frozen quantity targets and the same empirical refinement rule.

The adapted QuantLib solver accepts original real `Time` coordinates directly;
its curve and exercise/cash adapters use those coordinates. Date conversion is
needed only by the separately constructed unmodified VanillaOption baseline,
which the Greek adapter does not publish. The supplementary adapter therefore
removes that irrelevant date-round-trip exclusion while preserving the original
price comparator's checks. Keep endpoint-cash and analytical-boundary exclusions.
QuantLib's direct snapshot theta remains unavailable at time-zero stopping
conditions; the supplementary theta is a valuation-roll difference of prices.
Preserve both earlier calendar-restricted attempts, their source hashes and raw
output. No runtime or reference target changes accompany this correction.
