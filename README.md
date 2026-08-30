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
