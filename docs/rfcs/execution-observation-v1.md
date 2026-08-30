# Build, test, and verified reuse observation v1

## Decision

GitHub Actions publishes a structured execution observation for the
evidence-generator. The observation has three stages:

1. `EVIDENCE_BUILD` materializes a generated evidence bundle;
2. `SEMANTIC_TEST` verifies every generated-file digest in that bundle;
3. `VERIFIED_TEST_RECEIPT_REUSE` reuses the exact test receipt without running
   a consumer test.

The first two stages receive wall-clock milliseconds from the command that was
actually run and peak RSS from the runner when available. A reused or
unexecuted stage has `wall_ms: null`; `0` is never used as a substitute for a
missing execution. The repository has no product build or product test target,
so those two scope entries are explicitly `NOT_APPLICABLE` and also have
`wall_ms: null`.

## Authority and graph binding

`examples/execution-observation/main.gooo` declares the twelve observation
activities. CI resolves every activity with the pinned released Gooo binary
and stores the complete graph, source digest, semantic digest, and
activity-resolution digest. Every stage and denominator cell carries an
activity reference to that released semantic graph. Runtime measurements are
direct command receipts; log text is not an authority.

The reuse receipt is valid only when its producer stage, result digest, input
scope digest, runner digest, toolchain digest, and activity-resolution digest
match the current observation. The cache key, cache digest, and cache
authority are serialized fields and are independently checked. A receipt is
not a reusable success if its consumer execution count is non-zero or if its
authority has escalated to a repository write.

## Fixed denominator

The denominator has twelve cells and is never reduced while a case executes.

| # | Cell | Stage | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_EXECUTION_CORE | CORE_RELEASE | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | AUTHORITY | FOUNDATION | DRIVER |
| 3 | RUNNER_TOOLCHAIN | IDENTITY | FOUNDATION | DRIVER |
| 4 | INPUT_DIGEST | IDENTITY | FOUNDATION | DRIVER |
| 5 | BUILD_STAGE | BUILD | COHERENCE | OUTCOME |
| 6 | TEST_STAGE | TEST | COHERENCE | OUTCOME |
| 7 | REUSED_WORK | REUSE | COHERENCE | OUTCOME |
| 8 | CACHE_IDENTITY | REUSE | COHERENCE | GUARDRAIL |
| 9 | NOT_EXECUTED_STATE | AUTHORITY | REGRESSION | GUARDRAIL |
| 10 | PEAK_RSS | RESOURCE | REGRESSION | GUARDRAIL |
| 11 | IMPROVEMENT_BOUNDARY | IMPROVEMENT | REGRESSION | GUARDRAIL |
| 12 | HUMAN_DOSSIER | REPORT | REGRESSION | OUTCOME |

## Decision cases

The workflow evaluates the same denominator for every case:

| Case | Expected result |
|---|---|
| normal | 11 `CLOSED`, one `UNKNOWN` improvement boundary, one verified reuse |
| not-executed | build/test/reuse remain `UNKNOWN`, with null wall time |
| missing-reuse | missing receipt/cache is `UNKNOWN`, not a successful reuse |
| stale-cache | cache contradiction is `REFUTED` |
| mixed | `REFUTED` wins while the independent improvement `UNKNOWN` remains visible |

All `UNKNOWN` decisions retain `stage`, `step`, `reason`, `unknown_class`,
`next_operation`, and `blocked_by`. A known cache contradiction is not hidden
by a missing receipt. The evaluator therefore applies `REFUTED > UNKNOWN >
CLOSED` to both top-level decisions and dependency propagation.

## Improvement boundary and non-claims

The normal fixture has only one build/test timing pair. It reports the observed
integer timings for humans, but does not claim saved milliseconds. Both
improvement fields are `UNKNOWN` until an exact before/after pair has the same
runner, toolchain, input digest, activity-resolution digest, and command scope.
The workflow does not claim product build/test performance or generalized
consumer utility. Product work is `NOT_APPLICABLE`, and external adoption is
outside this bounded fixture.

The workflow writes only `$RUNNER_TEMP` artifacts. It verifies the source tree
digest before and after execution and requires zero source-repository writes.
The Actions job is the only place that runs the evidence build and test; no
local build, test, or formatter is part of this change.
