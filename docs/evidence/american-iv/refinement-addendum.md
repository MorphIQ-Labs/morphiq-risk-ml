# Domain refinement follow-up to the frozen inverse campaign

The first 128-cell, two-domain-expansion run preserves 24 accepted analytical
intervals and six PDE price-accuracy failures. No failed price was used as an
inverse sign. The recorded domain-refinement changes reject the wide search's
endpoint before inversion can finish. Keep that result as the original campaign.

Evaluate three domain expansions, preserving all 30 original quotes, [0.05,0.6]
search bounds, price refinement target 1, volatility widths 0.05 and 0.005, and
128 space/time cells. This extends the numerical stock domain and shifts the
three-domain comparison sequence outward; it does not relax its screens or the
independent containment criterion. Raise the explicit node allowance to 16,384
for this validation; all other recorded budgets remain fixed. Retain every
outcome, including any continuing refusal. This addendum is written before
scoring the expanded-domain configuration. It is not a revised pass criterion
for the initial run or a promise of broad availability.

The first expanded-domain harness retained six workspace refusals: the solver
reserves 512 bytes per allowed node, so asking for 16,384 nodes is incompatible
with the fixed 8 MiB budget after metadata. Inspection of the domain-extension
algorithm shows that it preserves interior nodes and adds geometrically growing
outer cells; this corpus does not need the larger node allowance. Retain that
failed attempt and restore the original 8,192-node/8 MiB limits for the next
three-domain run. The owning grid checks remain enforced. This is a resource
configuration correction, with all numerical targets and corpus inputs unchanged.
