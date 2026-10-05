# #111 implementation campaign protocol, version 1

Frozen before executing the new runtime against prices. Financial corpus and
references are the #110 original words. Do not alter epsilon or the #109 solver
policy after observing an outcome. Missing references cannot pass.

Two resource configurations are engineering experiments, not deployment defaults:

| Configuration | Base cells/steps | Domain doublings | Node cap | Step cap W | Policy cap | Row cap | Workspace bytes | Iterations/step |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| initial | 32 / 32 | 2 | 4096 | 4096 | 32768 | 50000000 | 4194304 | 32 |
| refined | 128 / 256 | 2 | 8192 | 32768 | 262144 | 400000000 | 8388608 | 32 |

Execute primary epsilon=2^-16 max(S,K) and epsilon/4. A zero-scale case uses
positive configuration tolerance 2^-16 and requires exactly zero output.
Record every success/failure and reference uncertainty; no last iterate is a
price. Use the same frozen scorer. Also collect a separately labelled **loose
capability experiment** at epsilon=max(S,K)/100, without treating its success as
meeting the primary goal. Retain its score at the primary goal as well.

The implementation uses backward Euler, at least three independent space/time
levels and three domains, boundary-pair solves, the fixed residual and roundoff
policy, and no Richardson correction. Arithmetic and accuracy failures are
expected outcomes to measure, not reasons to relax policy version 1.

Controls cover complete admission, signed rates/yields, deterministic interior
stopping, delayed opening, analytical reductions, scaling, all resource classes,
cancellation before allocation/during numerical work/before result publication,
roundoff under excessive W, and policy exhaustion. Native and bytecode execute
the public surface; numerical accuracy uses independent fixtures, not replay.

Scalar measurements separate admission and repeated price calls with/without
optional diagnostics. Record elapsed time, GC allocation, source/binary hashes,
compiler/profile, hardware/load and raw repeated-process observations. Successful
and unavailable pricing requests are distinct categories. This initial API has
no predecessor American runtime to compare against.
