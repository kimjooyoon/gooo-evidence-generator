# RFC: Separate meta and project graph authorities

## Problem

Generator v1 used one Gooo graph for two independent questions:

1. is a recurring generator pattern bound to meta code;
2. is a consumer readiness cell bound to domain code?

Self-hosting made both sets contain the same twelve activities. An unrelated
consumer graph cannot satisfy the generator-specific pattern activities, so a
valid domain activity loss could also demote an unrelated generator pattern.

## Decision

V2 requires two graph inputs.

- `meta_graph` is authoritative only for pattern promotion.
- `project_graph` is authoritative only for denominator-cell binding.
- generated reports preserve both graph hashes and both source digests.
- generated activity bindings contain project-graph node IDs only.

The generator source repository remains the authority for the pinned release
lock and repetition observation. Neither graph can authorize the other.

## Exact conformance cases

- self-host: meta `12`, project `12`, cells `12/12`, patterns `11/11`;
- captured external ledger: meta `12`, project `12`, cells `12/12`, patterns
  `11/11`, and the two graph hashes differ;
- missing project receipt activity: cells `9 CLOSED + 1 DIRECT_MISSING + 2
  DEPENDENCY_BLOCKED`, pattern changes `0`;
- duplicate project receipt activity: cells `9 CLOSED + 3 REFUTED`, pattern
  changes `0`;
- missing meta receipt activity: cells `12/12 CLOSED`, required patterns `1
  UNKNOWN`;
- unbound README requirement: cells `12/12 CLOSED`, required patterns `1
  REFUTED`.

## External-validity boundary

The captured ledger proves that the implementation accepts a different domain
graph. It does not count as an independent public adoption because it lives in
the generator repository. External validity remains `0/2` until two public
consumer repositories pin a released dual-graph generator and publish their
own CI evidence.

## Consumer release-lock compatibility

The repository argument supplies the consumer's core release lock. Requiring
the generator's exact schema ID or exact asset count would make the generator
its own only valid consumer. V2 therefore accepts a structural family whose
schema ends in `/core-release-lock/v1` and whose explicit repository, tag, tag
object, target commit, asset names, and SHA-256 values are present. The Linux
Gooo archive remains mandatory.

CI covers the generator lock with one asset and the captured local-ledger lock
shape with eight assets. It does not rewrite either lock into the other shape.
The former carries raw hexadecimal in `sha256`; the latter carries the
algorithm-qualified value in `digest`. Validation normalizes those values only
for comparison and preserves the original field vocabulary in generated output.

## Non-claims

Graph separation does not prove that generated contracts are useful, that the
consumer evidence is true at runtime, or that the compiler should absorb the
generator. It removes one measured authority collision and creates a testable
path to independent adoption.
