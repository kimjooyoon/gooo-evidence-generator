# gooo-evidence-generator

Deterministic evidence-project generation from released Gooo activity graphs.

This repository tests one narrow self-improvement loop for Gooo:

1. observe structures already used by four independent public projects;
2. promote a structure only when at least three projects use it;
3. reject promotion when the structure has no Gooo meta-activity;
4. generate a declarative evidence bundle outside the source repository;
5. let GitHub Actions establish replay, uncertainty, refutation, and digest
   behavior.

The generator does not emit executable CI or application code. It emits a
fixed denominator, activity bindings, a conformance plan, a generation report,
documentation, and a digest manifest. This keeps generated output reviewable
and prevents a template from silently becoming an authority.

## Exact v1 denominator

- observed public projects: `4`;
- promotion threshold: `3/4`;
- observed recurring patterns: `12`;
- meta-bound promoted patterns: `11`;
- excluded pattern without meta code: `1` (`root-readme`);
- Gooo activities: `12`;
- readiness cells: `12`;
- proof choices: `FOUNDATION 4`, `COHERENCE 4`, `REGRESSION 4`;
- generated files: `7`, including one manifest that covers the other `6`;
- required source-repository writes: `0`.

`README.md` exists as documentation, but root README presence is explicitly
excluded from readiness. Repetition alone is not enough: a metric or generated
pattern without a Gooo activity is not promoted.

## CI-only conformance target

GitHub Actions, not a local test run, must establish all of these outcomes:

- complete generation: `12 CLOSED / 0 UNKNOWN / 0 REFUTED`;
- missing receipt activity: `9 CLOSED / 1 DIRECT_MISSING / 2 DEPENDENCY_BLOCKED`;
- duplicate receipt activity: `9 CLOSED / 3 REFUTED`;
- required README pattern: `FAIL_CLOSED / REQUIRED_PATTERN_NOT_PROMOTED`;
- generated-file mutation: `5/6` manifest entries verified and `1 REFUTED`;
- deterministic replay: byte-identical output from two generations;
- source-repository writes: `0`;
- local test executions: `0`.

## Independence

The four observed projects are pinned historical evidence, not live build
dependencies. A consumer needs only a released Gooo CLI, its own `.gooo`
source, its own denominator, and its own profile. Linkers and generated
projects therefore cannot block the source projects that informed the pattern.

See [the v1 RFC](docs/rfcs/evidence-generator-v1.md) for the authority and
non-claim boundaries.

## Dual-graph v2

V1 deliberately proved self-hosting with one graph. That graph carried two
different authorities: generator-pattern promotion and consumer-cell binding.
V2 separates them:

- `meta graph` decides whether recurring generator patterns have exactly one
  Gooo meta-activity;
- `project graph` decides whether a consumer denominator has exactly one Gooo
  activity per cell;
- deleting a project activity cannot demote a generator pattern;
- deleting a meta activity cannot alter a consumer cell;
- both graph identities are preserved in every generated report.

CI also generates an external local-project ledger fixture with the unchanged
generator. This captured fixture is evidence for graph separation, not one of
the required two independent public consumer adoptions.

See [the v2 RFC](docs/rfcs/separate-meta-project-graphs-v2.md).

### Consumer lock compatibility

The generator validates the semantic release identity rather than requiring its
own lock-file shape. CI covers two valid lock contracts:

- `gooo/core-release-lock/v1` with `1` pinned Linux asset;
- `gooo/local-ledger/core-release-lock/v1` with all `8` release assets.

The first uses `sha256: <64hex>` as a dedicated field. The second preserves
GitHub's `digest: sha256:<64hex>` vocabulary. Both are validated as the same
hash algorithm without rewriting either serialized contract.

Both must produce `12/12 CLOSED`, `11` promoted patterns, and `6/6` verified
manifest entries. A lock is accepted only when its schema ends in
`/core-release-lock/v1`, its tag and commit identities are explicit, every
asset has a SHA-256 digest, and a Linux Gooo archive is present.

Release identity may be serialized in either of two structures:

- flat: `tag`, `tag_object_sha`, `target_commit_sha`, and `assets`;
- nested: `release.tag`, `release.tag_object.sha`, `release.target.sha`, and
  `release.assets`.

CI preserves both structures byte-for-byte within each generated bundle. The
generator normalizes only the fields needed for validation.

## Transformation effect receipt v1

The next self-improvement increment keeps source mutation forbidden and asks a
narrower question: can one evidence-backed, meta-bound candidate improve one
pinned generated-project fixture without changing its denominator or unrelated
cells?

The candidate is selected from the existing four-project repetition
observation. CI applies it only to a caller-owned temporary copy, evaluates an
exact `11 CLOSED / 1 UNKNOWN` before state and `12 CLOSED / 0 UNKNOWN` after
state, performs deterministic replay, and runs an independent conformer. A
known counterexample is REFUTED even when candidate evidence is also missing.

This closes one exact fixture pair, not a general language-value claim.
Independent external adoption remains `0/1 UNKNOWN`, build and test executions
remain zero, and the repository is never edited by the candidate. See
[the v1 effect RFC](docs/rfcs/transformation-effect-receipt-v1.md).

## Exact test receipt reuse v1

The next bounded loop distinguishes a test that ran from a test that merely
looks reusable. CI executes one released-Gooo semantic test, records its exact
input scope, toolchain, command, result digest, wall time, and peak RSS, then
asks an independent evaluator whether a consumer may reuse that receipt
without executing the test again.

Reuse closes only when all scope and result identities match. A missing
receipt remains UNKNOWN, while stale scope, an unrecognized receipt decision,
known result contradiction, or authority escalation is REFUTED. A mixed stale
and incomplete receipt is REFUTED rather than hidden by UNKNOWN.

The normal fixture records one producer test execution, one receipt reuse, and
zero consumer test executions. Saved test time remains UNKNOWN because this
experiment does not have an independent equivalent timing pair. See
[the test receipt reuse RFC](docs/rfcs/test-receipt-reuse-v1.md).

## Counterexample-guided revision v1

The counterexample-guided revision loop emits a minimal, caller-owned proposal
that lowers one claim's resolution. It preserves the input claim as `UNKNOWN`;
even a valid proposal never promotes that claim to `CLOSED`. Exact before/after
evidence is required for an improvement claim, so improvement remains
`UNKNOWN` in this fixture.

The evaluator records the exact causal `stage`, `step`, `reason`, unknown class,
next operation, blocked-by set, and frontier for direct missing, stale,
ambiguous, unbounded, and dependency-blocked evidence. Known counterexamples,
malformed evidence, an unrecognized upper decision, and `FIXED_POINT` fail
closed as `REFUTED`, which takes precedence over UNKNOWN in mixed cases.

Its fixed denominator is 12 cells and 12 one-to-one released Gooo activities:
`FOUNDATION 4 / COHERENCE 4 / REGRESSION 4` and
`DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`. CI covers normal, direct-missing,
dependency-blocked, stale, ambiguous, unbounded, counterexample, malformed,
`FIXED_POINT`, unrecognized-decision, and mixed cases. It writes no source
repository files and runs no local tests. See
[the counterexample-guided revision RFC](docs/rfcs/counterexample-guided-revision-v1.md).

## PREDECLARE to CONSUME_ONCE transition ticket v1

The temporal transition ticket closes the self-improvement ordering gap with
two explicit phases. `PREDECLARE` freezes predecessor identity and immutable
artifact/report digests, proposal and expected tree digest, target branch,
policy/toolchain/workflow digests, proof choice, expiry policy, nonce, and
ticket ID before a successor runs. `CONSUME_ONCE` closes only when the actual
successor, PR/merge receipt, and all frozen identities match; ticket reuse is
`REFUTED`. A squash merge commit SHA is intentionally resolved later through a
typed mapping from `expected_tree_digest` to the merge receipt tree digest.

The new contract keeps a fixed 12-cell denominator and 12 released Gooo
activities, with `FOUNDATION 4 / COHERENCE 4 / REGRESSION 4` and
`DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`. CI covers 18 exact cases: one normal
case, four UNKNOWN cases, and thirteen REFUTED cases, including mixed
`REFUTED`-over-`UNKNOWN`, post-hoc and retroactive closure rejection, digest
laundering, and authority/write escalation. It records 158 caller-owned
artifact files, repository writes `0`, local test executions `0`, and required
cross-project gates `0`; external utility and performance improvement remain
`UNKNOWN` without independent evidence. See
[the temporal transition ticket RFC](docs/rfcs/temporal-transition-ticket-v1.md).

## Build, test, and verified reuse observation v1

The execution observation workflow makes the evidence-generator's build and
test stages visible in the Actions summary with integer wall time and peak RSS
when available. `BUILD` is the caller-owned evidence bundle materialization;
`TEST` is the generated-bundle digest verification. They are direct command
receipts, not values parsed from log text. Each stage and each denominator cell
is bound to an activity in `examples/execution-observation/main.gooo` through
the released semantic graph and its activity-resolution digest.

The normal case records one executed build, one executed test, and one
`REUSED` exact test receipt. The receipt's cache key, digest, authority, input
digest, runner, toolchain, and released graph identity must match before reuse
closes. No consumer test is executed for the reused work. Product build/test
work is explicitly `NOT_APPLICABLE` for this repository, with `wall_ms: null`.

No unexecuted work is represented as `0 ms`; it is `NOT_EXECUTED` or `UNKNOWN`.
Because this fixture has no exact same-condition before/after pair, build-time
and test-time improvement remain `UNKNOWN`. The fixed 12-cell denominator is
preserved across normal, not-executed, missing-reuse, stale-cache, and mixed
cases, with `REFUTED` taking precedence over `UNKNOWN`.
