# Exact test receipt reuse v1

## Decision

Gooo may reuse a prior test result only when an exact, machine-readable receipt
binds the tested input scope, released toolchain, command, result, and execution
authority. The consumer independently compares those identities and executes
zero tests while making the reuse decision.

This is a bounded self-improvement step. It proves one released-Gooo semantic
test receipt can be reused for one exact scope. It does not prove that an
arbitrary Go, OpenTofu, or Gooo test suite is reusable, and it does not infer
saved time.

## Model

The producer executes exactly one semantic test and records:

- one source path and SHA-256 digest;
- released Gooo tag, commit, and binary SHA-256 digest;
- the exact command vector and Linux platform;
- diagnostics status, semantic hash, and result-file digest;
- integer wall milliseconds and peak RSS KiB;
- producer repository writes, source mutations, and local test executions.

The consumer receives the receipt and result as evidence. It recomputes their
digests, compares the receipt scope with the current scope, and emits a reuse
decision without executing the test command. Producer and consumer subject
commits are provenance, not equality keys: a later commit may reuse the receipt
only when every declared test-scope identity is unchanged.

## Fixed denominator

There are exactly 12 cells and 12 Gooo activities. Proof choices are
`FOUNDATION 4 / COHERENCE 4 / REGRESSION 4`. Indicator classes are
`DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`. No score or weighted aggregate exists.

| # | Cell | Activity | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_GOOO_IDENTITY | ObserveReleasedTestCore | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | BindTestReceiptReuseActivities | FOUNDATION | GUARDRAIL |
| 3 | SUBJECT_SCOPE | PinTestSubjectScope | FOUNDATION | DRIVER |
| 4 | BASELINE_TEST_EXECUTION | RecordBaselineTestExecution | FOUNDATION | OUTCOME |
| 5 | TEST_RECEIPT | PublishExactTestReceipt | COHERENCE | DRIVER |
| 6 | RECEIPT_IDENTITY | VerifyTestReceiptIdentity | COHERENCE | DRIVER |
| 7 | SCOPE_EQUIVALENCE | CompareTestScopeDigests | COHERENCE | OUTCOME |
| 8 | REUSE_DECISION | AuthorizeExactTestReceiptReuse | COHERENCE | OUTCOME |
| 9 | EXECUTION_AVOIDANCE | RecordReceiptReuseWithoutConsumerTest | REGRESSION | GUARDRAIL |
| 10 | UNKNOWN_CAUSALITY | PreserveTestReceiptUnknown | REGRESSION | GUARDRAIL |
| 11 | REFUTATION_PRECEDENCE | RefuteStaleOrContradictoryReceipt | REGRESSION | GUARDRAIL |
| 12 | HUMAN_REPORT | PublishTestReceiptReuseReport | REGRESSION | OUTCOME |

## Exact cases

| Case | Cells | Top decision |
|---|---:|---|
| normal | 12 CLOSED / 0 UNKNOWN / 0 REFUTED | TEST_RECEIPT_REUSE_CLOSED |
| missing-receipt | 5 CLOSED / 7 UNKNOWN / 0 REFUTED | TEST_RECEIPT_REUSE_UNKNOWN |
| stale-scope | 8 CLOSED / 0 UNKNOWN / 4 REFUTED | FAIL_CLOSED |
| refuted-over-unknown | 7 CLOSED / 1 UNKNOWN / 4 REFUTED | FAIL_CLOSED |
| authority-escalation | 10 CLOSED / 0 UNKNOWN / 2 REFUTED | FAIL_CLOSED |
| unrecognized-decision | 7 CLOSED / 0 UNKNOWN / 5 REFUTED | FAIL_CLOSED |

Every UNKNOWN has `stage`, `step`, `reason`, `unknown_class`,
`next_operation`, and `blocked_by`. A direct stale-scope contradiction is
REFUTED even when receipt result evidence is also missing. Only the explicit
receipt decision `PASS` is accepted; `FIXED_POINT` and every other value fail
closed.

## Metrics and non-claims

The normal case observes exactly one producer test execution, one receipt
reuse, and zero consumer test executions. This establishes
`receipt_reuse_without_consumer_execution = 1/1` for the fixture.

`saved_test_ms` remains UNKNOWN. The producer execution time and consumer
validation time are different operations and are not silently treated as an
equivalent before/after pair. Cross-run public adoption and external user
utility also remain UNKNOWN until independent evidence exists.

CI records exact wall time, peak RSS, artifact count, source inventory, and
authority counters. Root README is excluded from readiness and inventory.

## Authority and falsification

The evaluator may read inputs and released Gooo evidence and may write only to
caller-owned temporary output. It may not run the test command, mutate source,
change the denominator, or promote a result from prose or a digest alone.

The normal claim is refuted by any scope mismatch, result digest mismatch,
semantic-hash contradiction, non-PASS decision, source mutation, repository
write, consumer test execution, denominator change, replay mismatch, or failure
to bind all 12 released Gooo activities.
