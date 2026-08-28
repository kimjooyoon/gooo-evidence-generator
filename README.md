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
