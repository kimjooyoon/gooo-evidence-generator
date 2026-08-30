# Counterexample-guided revision v1

## Decision

The evidence generator may produce a caller-owned revision proposal that lowers
one claim's resolution, but it may not promote the input claim to `CLOSED` and
may not edit the source repository. The proposal is a bounded artifact, not
evidence that the proposed change improved the system. Without an exact
before/after pair, the improvement claim remains `UNKNOWN`.

The evaluator first establishes a causal boundary. It preserves the exact
`stage`, `step`, `reason`, `unknown_class`, `next_operation`, `blocked_by`, and
frontier coordinates for `DIRECT_MISSING`, `STALE`, `AMBIGUOUS`, `UNBOUNDED`,
and `DEPENDENCY_BLOCKED`. A frontier is minimal and points to the smallest
unresolved coordinate that can change the proposal.

Known contradictions have precedence over UNKNOWN. An observed semantic
counterexample, malformed evidence, an unrecognized upper decision, and the
literal `FIXED_POINT` are `REFUTED` and fail closed. A mixed input can therefore
retain an independent stale UNKNOWN cell while the overall decision is
`FAIL_CLOSED` because a counterexample is present.

## Fixed denominator

There are exactly 12 cells and exactly 12 released Gooo activities. Proof
choices are `FOUNDATION 4 / COHERENCE 4 / REGRESSION 4`, and indicator classes
are `DRIVER 4 / OUTCOME 4 / GUARDRAIL 4`.

| # | Cell | Activity | Proof | Indicator |
|---:|---|---|---|---|
| 1 | RELEASED_GOOO_IDENTITY | ObserveReleasedRevisionCore | FOUNDATION | DRIVER |
| 2 | META_ACTIVITY_AUTHORITY | BindRevisionActivities | FOUNDATION | GUARDRAIL |
| 3 | CLAIM_INPUT | ObserveInputClaim | FOUNDATION | DRIVER |
| 4 | REVISION_SCOPE | BoundRevisionScope | FOUNDATION | OUTCOME |
| 5 | CAUSAL_FRONTIER | LocateCausalFrontier | COHERENCE | DRIVER |
| 6 | COUNTEREXAMPLE_RECEIPT | ObserveRevisionCounterexample | COHERENCE | OUTCOME |
| 7 | RESOLUTION_BOUNDARY | SelectResolutionBoundary | COHERENCE | DRIVER |
| 8 | REVISION_PROPOSAL | GenerateRevisionProposal | COHERENCE | OUTCOME |
| 9 | REPLAY_GUARD | VerifyRevisionReplay | REGRESSION | GUARDRAIL |
| 10 | UNKNOWN_TRACE | PreserveRevisionUnknown | REGRESSION | GUARDRAIL |
| 11 | REFUTATION_PRECEDENCE | PrioritizeRevisionRefutation | REGRESSION | GUARDRAIL |
| 12 | HUMAN_DOSSIER | PublishRevisionHumanDossier | REGRESSION | OUTCOME |

## Scenarios

CI executes the same evaluator and independent conformer for these cases:

| Case | Expected boundary |
|---|---|
| normal | valid `CLOSED` proposal; input claim remains `UNKNOWN` |
| direct-missing | `UNKNOWN / DIRECT_MISSING` |
| dependency-blocked | `UNKNOWN / DEPENDENCY_BLOCKED` |
| stale | `UNKNOWN / STALE` |
| ambiguous | `UNKNOWN / AMBIGUOUS` |
| unbounded | `UNKNOWN / UNBOUNDED` |
| counterexample | `REFUTED` with partial output `0` |
| malformed | `REFUTED` for malformed evidence |
| fixed-point | `REFUTED` for `FIXED_POINT` |
| unrecognized-decision | `REFUTED` for an unknown upper decision |
| mixed | `REFUTED` counterexample plus retained `STALE` UNKNOWN |

The normal output is generated twice and compared byte-for-byte. Every output
contains a revision proposal, causal frontier, counterexample record, and
human dossier. The manifest covers the six machine-readable/text artifacts;
the manifest itself makes seven files in the caller-owned output directory.

## Authority and non-claims

The evaluator can read the claim, proposal, evidence, denominator, and released
activity receipts. It writes only to a caller-owned temporary output directory.
Source mutation, repository writes, automatic claim promotion, local tests,
and automatic improvement claims are forbidden. The workflow uses Go 1.27 and
does not run a local test command; conformance is established by GitHub Actions
only.
