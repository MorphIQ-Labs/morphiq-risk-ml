# Optional American policy backend experiment

The default library keeps its current bounded native solver. These original
project adapters are installed only into a fresh isolated source tree by:

```sh
python3 scripts/build_american_backends.py --output /tmp/american-backend-build
```

The optional build requires `gfortran`, `ar`, the project OCaml switch and network
access to the pinned Reference LAPACK files. `upstream.json` freezes both source
and license hashes. DGTSV is unchanged; an original C `xerbla_` shim retains INFO
instead of invoking the upstream fatal error printer. Dimensions are validated
before calls. No BLAS routine, vendor dispatch or nested thread pool is linked.
Compiler/version/flags, source hashes and patches are retained in the output.
The OCaml custom-operations identity check deliberately targets the pinned 5.3
runtime ABI; it is not a portable public foreign interface.

`owner.ml` selects `native`, `ocaml` or `lapack` once at process startup via
`MORPHIQ_POLICY_BACKEND`. The original source remains untouched. Native campaign
timings use the unmodified production owner in the main checkout; the native
adapter is used only for capture. OCaml changes elimination/substitution only,
using the existing original-project operation reference. LAPACK replaces that
solve with a whole-system call using call-owned float64 C-layout Bigarrays.
All model admission, assembly, policy decisions, original-system residuals,
events and refinements stay in their original owners.

The LAPACK wrapper validates LP64/binary64 sizes, shapes/aliases, finite inputs,
INFO, finite outputs, nearest rounding and gradual underflow. The caller's FP
environment is restored after the call, including error exits. The rooted
Bigarray stores native scratch; no pointer is retained or runtime lock released.
Scratch costs 32 bytes per interior unknown per owner, in addition to existing
managed bands. `MORPHIQ_POLICY_ACCOUNT=1` counts cumulative native scratch bytes
and owners in a separate untimed process. Those bytes are not included in OCaml
managed allocation counters; RSS covers the whole child process.

**This is not a production-ready adapter.** The whole solve occurs at the first
elimination block; later block visits preserve logical counts but cannot undo
physical work. It does not preserve bounded callback/cancellation points,
partial native failure writes or a complete production workspace reservation.
`backend_contracts` retains both callback/resource traces and a direct witness:
requesting one elimination row can fill the whole candidate vector under the
LAPACK proxy. Numerical differences are retained, not accepted by replay alone.
Production adoption requires separate derivation and complete qualification.

Capture is opt-in through `MORPHIQ_POLICY_TRACE`, restricted to the main domain.
It samples fixed policy ordinals per reached dimension after boundary removal,
then records original coefficients, RHS, selected mask, local allowance and
baseline solution. `MORPHIQ_CAPTURE_CELLS` changes only the optional harness grid
for the separately declared 256-cell capture. It never changes production API
configuration or the frozen 64-cell request timing campaign.

See the [frozen protocol](../../docs/evidence/american-backends/protocol.md).
The controller's `qualify` phase generates matrices and exact-rational checks;
`measure` requires matching qualification/source/binary identities. Outputs must
be fresh directories outside both source trees. Default CI exercises small
parser and exact-residual controls without downloading or building LAPACK.
