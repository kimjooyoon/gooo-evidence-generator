# Transformation effect receipt v1

## Decision

This experiment adds one bounded self-improvement step without granting a
generator permission to edit its own source. Released Gooo meta activities
select one evidence-backed candidate, the candidate is applied to one pinned
fixture in caller-owned temporary storage, and an independent conformer decides
whether the exact before/after effect is acceptable.

The normal fixture effect is a closed claim. General language improvement and
external utility remain UNKNOWN.

## Prior work adopted and rejected

Program synthesis by sketching uses a candidate, validator, and counterexample
loop. We adopt that separation and the rule that a counterexample refines or
rejects a candidate; we do not adopt unconstrained program synthesis or infer a
candidate from natural-language similarity:

- https://www2.eecs.berkeley.edu/Pubs/TechRpts/2008/EECS-2008-176.html

Translation validation checks each concrete translator run rather than treating
the translator implementation as trusted. We adopt per-transformation
validation and keep the candidate producer outside the conformance authority:

- https://doi.org/10.1007/BFb0054170
- https://web.ist.utl.pt/nuno.lopes/pubs.php?id=alive2-pldi21

Alive2 is explicitly bounded. We adopt the honesty of a bounded result and
reject a language-wide equivalence claim: this experiment proves one fixture,
one candidate, one denominator, and one released toolchain only. It does not
use an SMT solver and does not claim semantic equivalence for arbitrary Gooo
programs.

## User path

1. Observe the pinned four-project pattern corpus.
2. Select `explicit-unknown` only because support is exactly `4/4`, the fixed
   threshold is `3`, and `PreserveUnknownTrace` exists in the released Gooo
   graph.
3. Read a pinned generated-project fixture with `11 CLOSED / 1 UNKNOWN`.
4. Apply one authorized transition to `UNKNOWN_TRACE` in caller-owned temporary
   storage.
5. Evaluate the exact before/after pair, replay it, and reject unrelated change.
6. Publish nine deterministic files and let an independent conformer recompute
   their digests and semantic counts.

No source repository, branch, pull request, release, issue, deployment, or
external project is changed by the candidate.

## Fixed denominator

The denominator has exactly 12 cells and exactly 12 released Gooo activity
bindings. Proof choices are `FOUNDATION 4 / COHERENCE 4 / REGRESSION 4`.
Indicators are `DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`. They are never aggregated
into a score.

| # | Cell | Gooo activity | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_GOOO_IDENTITY | ObserveReleasedImprovementCore | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | BindTransformationEffectActivities | FOUNDATION | GUARDRAIL |
| 3 | PATTERN_OBSERVATION | ObserveCandidatePatternSupport | FOUNDATION | DRIVER |
| 4 | CANDIDATE_SELECTION | SelectMetaBoundCandidate | FOUNDATION | OUTCOME |
| 5 | BASELINE_SNAPSHOT | PinBaselineProjectSnapshot | COHERENCE | DRIVER |
| 6 | ISOLATED_APPLICATION | ApplyCandidateToIsolatedProject | COHERENCE | OUTCOME |
| 7 | BEFORE_AFTER_EVALUATION | EvaluateCandidateBeforeAndAfter | COHERENCE | DRIVER |
| 8 | EXACT_EFFECT_RECEIPT | PublishExactTransformationEffect | COHERENCE | OUTCOME |
| 9 | DENOMINATOR_PRESERVATION | PreserveFixedDenominator | REGRESSION | GUARDRAIL |
| 10 | DETERMINISTIC_REPLAY | VerifyTransformationReplay | REGRESSION | OUTCOME |
| 11 | UNKNOWN_CAUSALITY | PreserveTransformationUnknown | REGRESSION | GUARDRAIL |
| 12 | REFUTED_COUNTEREXAMPLE | RefuteTransformationCounterexample | REGRESSION | GUARDRAIL |

## Exact cases

There are exactly four semantic cases. The normal case is executed twice for
whole-output replay.

| Case | Process cells | Decision |
|---|---:|---|
| normal | 12 CLOSED / 0 UNKNOWN / 0 REFUTED | TRANSFORMATION_EFFECT_CLOSED |
| missing-pattern | 5 CLOSED / 7 UNKNOWN / 0 REFUTED | INCOMPLETE |
| unauthorized-operation | 6 CLOSED / 0 UNKNOWN / 6 REFUTED | FAIL_CLOSED |
| refuted-over-unknown | 4 CLOSED / 2 UNKNOWN / 6 REFUTED | FAIL_CLOSED |

The mixed case deliberately contains a missing pattern and a known baseline
counterexample. The top-level claim is REFUTED, proving that a contradiction
outranks UNKNOWN. Every UNKNOWN record has `stage`, `step`, `reason`,
`unknown_class`, `next_operation`, and `blocked_by`.

## Exact effect and non-claims

The sole recognized fixture improvement is:

- total cells: `12 -> 12`, delta `0`;
- CLOSED: `11 -> 12`, delta `+1`;
- UNKNOWN: `1 -> 0`, delta `-1`;
- REFUTED: `0 -> 0`, delta `0`;
- target transitions: `1`;
- unrelated cell changes: `0`;
- exact comparable pairs: `1/1`.

The pair is comparable only because fixture, candidate, observation,
denominators, released activity resolution, subject commit, and toolchain
identities are digest-bound. Any mismatch makes the claim UNKNOWN or REFUTED;
the evaluator never silently changes the denominator.

Generalized language improvement is `0/1 UNKNOWN`. External user utility is
`0/1 UNKNOWN`. No time or memory improvement is claimed because there is no
equivalent performance before/after pair.

## Generated and CI artifacts

Each evaluator output contains exactly nine files: one manifest covering the
other eight, candidate selection, before project and evaluation, after project
and evaluation, activity bindings, effect receipt, and a human report.

The CI artifact contains exactly 56 files:

- five evaluator outputs times nine files: `45`;
- five independent conformer reports: `5`;
- one runtime observation: `1`;
- released version, syntax, semantic, graph, and activity-resolution receipts:
  `5`.

## Runtime and inventory metrics

CI records integer wall milliseconds and peak RSS KiB for the normal evaluator,
plus exact repository regular-file, descendant-directory, physical-line, Go
line, and Gooo line counts. Per-file Go and Gooo physical lines are included.
The root README is excluded from inventory and is never a readiness predecessor.

Go is pinned to `1.27.0`. Gooo version, syntax, semantic, and graph commands each
execute once. Go build, Go test, product build, product test, and local test
executions are exactly zero. A released binary is reused once; released test
receipt reuse and saved build/test time remain UNKNOWN rather than inferred.

## Authority and falsification

Allowed operations are released CLI observation, read-only input inspection,
and creation of caller-owned temporary artifacts. Forbidden operations include
repository writes, source mutation, denominator reduction, automatic
promotion, remote writes, and claiming external utility from CI.

This experiment is REFUTED by any of the following:

- the selected pattern is not uniquely meta-bound;
- the candidate changes any cell other than `UNKNOWN_TRACE`;
- the denominator changes;
- exact before/after integers differ from the candidate contract;
- replay differs;
- a known counterexample is reported as UNKNOWN or CLOSED;
- the manifest, subject, or input digest does not recompute;
- source repository writes, builds, or tests are nonzero.
