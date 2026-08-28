# RFC: Released-graph evidence generation v1

## Decision

Generate declarative evidence-project contracts from a released Gooo activity
graph. Do not generate executable workflow code, application code, Terraform,
or deployment commands in v1.

## Observed basis

Four independent public Gooo consumers provide the historical observation
denominator. A pattern is support-eligible when at least `3/4` sources contain
it. Support is necessary but insufficient: promotion also requires a named
Gooo activity that occurs exactly once in the released graph.

The observation contains `12` patterns. All `12` meet the support threshold,
but only `11` have meta-activity bindings. `root-readme` is therefore excluded
from readiness even though all four repositories contain a README. This is the
deliberate counterexample to "repetition implies semantic authority."

## Generated boundary

One invocation writes exactly seven files to a caller-provided external output
directory:

1. pinned core release lock;
2. fixed evidence denominator;
3. released-graph activity bindings;
4. declarative conformance plan;
5. non-authoritative generated documentation;
6. generation report;
7. digest manifest covering the preceding six files.

The generator refuses an output path equal to or below the source repository
and refuses a non-empty output directory. It never edits a consumer project.

## Resolution rules

- exactly one graph activity for a cell closes the direct binding;
- zero occurrences produce `UNKNOWN / DIRECT_MISSING`;
- a predecessor that is unknown produces `UNKNOWN / DEPENDENCY_BLOCKED`;
- multiple occurrences produce `REFUTED / AMBIGUOUS_ACTIVITY_BINDING`;
- a refuted predecessor produces `REFUTED / DEPENDENCY_REFUTED`;
- a required pattern without sufficient support or a unique meta-activity
  produces `FAIL_CLOSED / REQUIRED_PATTERN_NOT_PROMOTED`;
- a generated digest mismatch produces
  `FAIL_CLOSED / GENERATED_FILE_DIGEST_MISMATCH`.

Every non-closed claim carries a stage, step, reason, next operation, and any
blocking predecessor IDs. Proof choices are the Munchausen categories
`FOUNDATION`, `COHERENCE`, and `REGRESSION`; they are not scores.

## Independence rule

Source repository SHAs are immutable observation references. Generator CI does
not query those projects and their current status cannot block generation. A
consumer pins a released Gooo CLI and owns its own denominator and CI. Optional
link projects may consume released artifacts but never become readiness
predecessors of the source projects.

## Self-improvement boundary

This is proposal generation, not autonomous source rewriting. A future pattern
may enter the generator only after its support count and meta binding are
represented as data and its adversarial CI outcome is preserved. Adoption into
the compiler remains a separate reviewed decision.

## Non-claims

V1 does not claim that generated contracts are correct for every domain, that a
passing graph proves runtime behavior, that repetition proves usefulness, or
that lower wall time or memory has improved anything. Runtime resources are
observations only until two explicitly comparable populations and a comparison
rule exist.
