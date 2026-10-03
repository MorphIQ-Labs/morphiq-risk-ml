/* Benchmark-only monotonic wall clock. No pricing arithmetic or runtime-library
   dependency. The boxed result may allocate, so this is not a noalloc primitive.
   CLOCK_MONOTONIC is supported on the three CI platforms. */
#include <time.h>
#include <caml/alloc.h>
#include <caml/fail.h>
#include <caml/mlvalues.h>

CAMLprim value morphiq_bench_monotonic(value unit)
{
  struct timespec now;
  (void)unit;
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0)
    caml_failwith("benchmark clock_gettime failed");
  return caml_copy_double((double)now.tv_sec + (double)now.tv_nsec * 1e-9);
}
