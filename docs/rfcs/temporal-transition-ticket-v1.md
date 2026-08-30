# PREDECLARE to CONSUME_ONCE transition ticket v1

## Decision

The self-improvement loop uses a two-phase transition ticket. `PREDECLARE`
must complete before a successor is executed or merged. `CONSUME_ONCE` may
close exactly one successor transition, and a second use of the same ticket is
`REFUTED`. A ticket is not a post-hoc exception and cannot retroactively close
a historical failure in `meta-ontology-go`.

The ticket freezes the predecessor identity, immutable predecessor artifact and
report digests, proposal/patch digest, expected tree digest, target branch,
policy digest, toolchain digest, workflow digest, expected proof choice, expiry
policy, expiry instant, nonce, and ticket ID. The successor commit SHA is
intentionally not predeclared: a squash merge can produce it later. Consumption
therefore requires a typed `SQUASH_COMMIT_TO_EXPECTED_TREE` mapping whose merge
receipt tree digest equals the predeclared expected tree digest and the actual
successor tree digest.

## Fixed denominator

There are exactly 12 cells and 12 released Gooo activities. Munchausen proof
choices are fixed at `FOUNDATION 4 / COHERENCE 4 / REGRESSION 4`; indicator
classes are fixed at `DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`. The denominator is
never reduced while a case is executing.

| # | Cell | Phase | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_GOOO_IDENTITY | CORE_RELEASE | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | AUTHORITY | FOUNDATION | GUARDRAIL |
| 3 | PREDECESSOR_IDENTITY | PREDECLARE | FOUNDATION | DRIVER |
| 4 | PREDECESSOR_ARTIFACT_REPORT | PREDECLARE | FOUNDATION | DRIVER |
| 5 | PROPOSAL_TREE_EXPECTATION | PREDECLARE | COHERENCE | GUARDRAIL |
| 6 | TRANSITION_POLICY | PREDECLARE | COHERENCE | OUTCOME |
| 7 | TICKET_LIFETIME_NONCE | PREDECLARE | COHERENCE | OUTCOME |
| 8 | PREDECLARE | PREDECLARE | COHERENCE | OUTCOME |
| 9 | SUCCESSOR_MERGE_RECEIPT | CONSUME | REGRESSION | DRIVER |
| 10 | CONSUME_ONCE | CONSUME | REGRESSION | OUTCOME |
| 11 | DECISION_PRECEDENCE | DECISION | REGRESSION | GUARDRAIL |
| 12 | HUMAN_DOSSIER | REPORT | REGRESSION | GUARDRAIL |

## Decision cases

The CI matrix keeps the same 12-cell denominator for every case:

| Case | Expected result |
|---|---|
| normal | `CLOSED`, PREDECLARE then one CONSUME_ONCE |
| prepared-not-consumed | `UNKNOWN`, receipt not yet available |
| missing-predecessor-artifact | `UNKNOWN`, immutable predecessor artifact/report missing |
| expired-stale | `UNKNOWN`, ticket stale under its expiry policy |
| dependency-blocked | `UNKNOWN`, predecessor identity dependency unavailable |
| target/tree/policy/toolchain/workflow mismatch | `REFUTED` |
| consume-before-prepare | `REFUTED` |
| replay-reuse | `REFUTED` |
| digest-laundering | `REFUTED` |
| unknown-top-level-decision | `REFUTED` |
| post-hoc-ticket | `REFUTED` |
| retroactive-closure | `REFUTED` |
| authority-write-escalation | `REFUTED` |
| mixed | `REFUTED` wins while stale UNKNOWN cells remain visible |

`REFUTED > UNKNOWN > CLOSED` applies both to dependency propagation and to the
top-level decision. Every `UNKNOWN` cell carries `stage`, `step`, `reason`,
`unknown_class`, `next_operation`, and `blocked_by`, plus a non-empty minimal
causal frontier. The mixed case proves that a contradiction is not hidden by
an independent stale frontier.

## Authority and non-claims

The evaluator writes only caller-owned temporary output. It cannot mutate the
input repository, lower the fixed denominator, issue a ticket after the
successor, or close an old failed transition. `repository_writes`, local test
executions, and cross-project required gates are zero. External utility and
performance improvement remain `UNKNOWN` because this fixture supplies no
independent utility evidence or comparable before/after performance pair.

The workflow uses Go 1.27 and a released Gooo binary. No local test or build is
run; GitHub Actions supplies the generation, evaluator, conformer, replay,
inventory, and artifact evidence.
