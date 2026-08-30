#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "usage: conform-counterexample-guided-revision-v1.sh OUTPUT DENOMINATOR CLAIM PROPOSAL EVIDENCE ACTIVITY_RESOLUTION SCENARIO REPORT" >&2
  exit 64
fi

output=$(realpath "$1")
denominator=$2
claim=$3
proposal=$4
evidence=$5
activity_resolution=$6
scenario=$7
report=$8

expected_files=(activity-bindings.json causal-frontier.json counterexample.json evaluation.json human-dossier.md manifest.json revision-proposal.json)
test "$(find "$output" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 8
for relative_path in "${expected_files[@]}"; do
  test -f "$output/$relative_path"
done

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

denominator_digest=$(json_digest "$denominator")
claim_digest=$(json_digest "$claim")
proposal_digest=$(json_digest "$proposal")
evidence_digest=$(json_digest "$evidence")
activity_resolution_digest=$(json_digest "$activity_resolution")

manifest="$output/manifest.json"
evaluation="$output/evaluation.json"
revision="$output/revision-proposal.json"
frontier="$output/causal-frontier.json"
counterexample="$output/counterexample.json"

jq -e --arg scenario "$scenario" '.schema=="gooo/evidence-generator/counterexample-guided-revision/manifest/v1" and .scenario==$scenario and .tracked_file_count==6 and (.files|length)==6 and ([.files[].path]|sort)==["activity-bindings.json","causal-frontier.json","counterexample.json","evaluation.json","human-dossier.md","revision-proposal.json"]' "$manifest" >/dev/null
verified=0
while IFS=$'\t' read -r relative_path expected_digest expected_size; do
  case "$relative_path" in /*|*..*) exit 65 ;; esac
  test "$(sha256sum "$output/$relative_path" | awk '{print $1}')" = "$expected_digest"
  test "$(wc -c < "$output/$relative_path" | tr -d ' ')" -eq "$expected_size"
  verified=$((verified+1))
done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
test "$verified" -eq 6

jq -e \
  --arg scenario "$scenario" \
  --arg denominator "$denominator_digest" \
  --arg claim "$claim_digest" \
  --arg proposal "$proposal_digest" \
  --arg evidence "$evidence_digest" \
  --arg resolution "$activity_resolution_digest" '
  .schema=="gooo/evidence-generator/counterexample-guided-revision/evaluation/v1" and
  .scenario==$scenario and .input_digests=={
    denominator:$denominator,claim:$claim,proposal:$proposal,evidence:$evidence,
    activity_resolution:$resolution} and
  .summary.total==12 and .summary.closed+.summary.unknown+.summary.refuted==12 and
  ([.cells[]|select(.proof_choice=="FOUNDATION")]|length)==4 and
  ([.cells[]|select(.proof_choice=="COHERENCE")]|length)==4 and
  ([.cells[]|select(.proof_choice=="REGRESSION")]|length)==4 and
  ([.cells[]|select(.indicator_class=="DRIVER")]|length)==4 and
  ([.cells[]|select(.indicator_class=="OUTCOME")]|length)==4 and
  ([.cells[]|select(.indicator_class=="GUARDRAIL")]|length)==4 and
  all(.cells[]; (.state=="CLOSED" or .state=="UNKNOWN" or .state=="REFUTED")) and
  all(.cells[]|select(.state=="UNKNOWN");
    (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
    (.unknown_class|type)=="string" and (.next_operation|type)=="string" and
    (.blocked_by|type)=="array" and (.frontier|type)=="array" and (.frontier|length)>0) and
  all(.cells[]|select(.state=="REFUTED");
    .unknown_class==null and (.blocked_by|type)=="array" and (.frontier|type)=="array") and
  .input_claim_promoted==false and .authority.repository_writes==0 and
  .authority.source_mutations==0 and .authority.automatic_claim_promotion==false and
  .authority.local_test_executions==0 and .improvement_claim.state=="UNKNOWN" and
  .improvement_claim.reason=="EXACT_BEFORE_AFTER_PAIR_ABSENT"
' "$evaluation" >/dev/null

jq -e \
  --arg scenario "$scenario" \
  --arg claim_id "$(jq -r '.id' "$claim")" \
  --arg claim_digest "$claim_digest" \
  --arg proposal_digest "$proposal_digest" '
  .schema=="gooo/evidence-generator/counterexample-guided-revision/revision-proposal/v1" and
  .scenario==$scenario and .target_claim_id==$claim_id and
  .input_claim_promoted==false and .input_claim_state_before=="UNKNOWN" and
  .input_claim_state_after=="UNKNOWN" and .input_claim==.input_claim_after and
  .proposed_change.operation=="LOWER_RESOLUTION_ONLY" and
  .proposed_change.from_resolution=="HIGH" and .proposed_change.to_resolution=="MEDIUM" and
  .proposed_change.changed_paths==["resolution"] and .proposed_change.applied==false and
  .authority.repository_writes==0 and .authority.source_mutations==0 and
  .exact_before_after.available==false and .improvement_claim.state=="UNKNOWN" and
  .input_digests.claim==$claim_digest and .input_digests.proposal==$proposal_digest
' "$revision" >/dev/null

jq -e '
  .schema=="gooo/evidence-generator/counterexample-guided-revision/activity-bindings/v1" and
  .summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12} and
  (.bindings|length)==12 and ([.bindings[].id]|unique|length)==12 and
  ([.bindings[].activity]|unique|length)==12
' "$output/activity-bindings.json" >/dev/null

jq -e '.schema=="gooo/evidence-generator/counterexample-guided-revision/causal-frontier/v1" and .minimal==true and .precedence=="REFUTED_OVER_UNKNOWN" and (.frontier|length)>=1 and (.claim.state=="UNKNOWN" or .claim.state=="REFUTED")' "$frontier" >/dev/null
jq -e '.schema=="gooo/evidence-generator/counterexample-guided-revision/counterexample/v1" and .partial_output==0 and .source_mutation==0 and (.input_digest|length)==64' "$counterexample" >/dev/null

case "$scenario" in
  normal)
    jq -e '.decision=="REVISION_PROPOSAL_CLOSED" and .proposal_status=="CLOSED" and .summary=={total:12,closed:12,unknown:0,refuted:0,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="UNKNOWN" and .claim.reason=="INPUT_CLAIM_NOT_PROMOTED" and .input_claim_promoted==false' "$evaluation" >/dev/null
    jq -e '.decision=="CLOSED" and .input_claim_promoted==false and .improvement_claim.state=="UNKNOWN"' "$revision" >/dev/null
    jq -e '.present==false and .state=="ABSENT"' "$counterexample" >/dev/null
    ;;
  direct-missing)
    jq -e '.decision=="REVISION_PROPOSAL_UNKNOWN" and .summary=={total:12,closed:2,unknown:10,refuted:0,direct_missing:1,stale:0,ambiguous:0,unbounded:0,dependency_blocked:9} and .claim.state=="UNKNOWN" and .claim.unknown_class=="DIRECT_MISSING" and .claim.stage=="EVIDENCE" and .claim.step=="OBSERVE_INPUT_CLAIM" and .claim.blocked_by==[]' "$evaluation" >/dev/null
    ;;
  dependency-blocked)
    jq -e '.decision=="REVISION_PROPOSAL_UNKNOWN" and .summary=={total:12,closed:2,unknown:10,refuted:0,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:10} and .claim.state=="UNKNOWN" and .claim.unknown_class=="DEPENDENCY_BLOCKED" and .claim.stage=="DEPENDENCY" and .claim.step=="RESOLVE_UPSTREAM_DECISION" and .claim.blocked_by==["UPSTREAM_DECISION"]' "$evaluation" >/dev/null
    ;;
  stale)
    jq -e '.decision=="REVISION_PROPOSAL_UNKNOWN" and .summary=={total:12,closed:7,unknown:5,refuted:0,direct_missing:0,stale:1,ambiguous:0,unbounded:0,dependency_blocked:4} and .claim.state=="UNKNOWN" and .claim.unknown_class=="STALE" and .claim.stage=="FRESHNESS" and .claim.step=="VERIFY_EVIDENCE_FRESHNESS"' "$evaluation" >/dev/null
    ;;
  ambiguous)
    jq -e '.decision=="REVISION_PROPOSAL_UNKNOWN" and .summary=={total:12,closed:6,unknown:6,refuted:0,direct_missing:0,stale:0,ambiguous:1,unbounded:0,dependency_blocked:5} and .claim.unknown_class=="AMBIGUOUS" and .claim.stage=="BOUNDARY" and .claim.step=="DISAMBIGUATE_REVISION_BOUNDARY"' "$evaluation" >/dev/null
    ;;
  unbounded)
    jq -e '.decision=="REVISION_PROPOSAL_UNKNOWN" and .summary=={total:12,closed:6,unknown:6,refuted:0,direct_missing:0,stale:0,ambiguous:0,unbounded:1,dependency_blocked:5} and .claim.unknown_class=="UNBOUNDED" and .claim.stage=="BOUNDARY" and .claim.step=="BOUND_REVISION_SCOPE"' "$evaluation" >/dev/null
    ;;
  counterexample)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:6,unknown:0,refuted:6,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="OBSERVED_REVISION_COUNTEREXAMPLE" and .claim.unknown_class==null' "$evaluation" >/dev/null
    jq -e '.present==true and .state=="REFUTED" and .partial_output==0' "$counterexample" >/dev/null
    ;;
  malformed)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="MALFORMED_REVISION_EVIDENCE" and .claim.unknown_class==null' "$evaluation" >/dev/null
    ;;
  fixed-point)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="FIXED_POINT_UPPER_DECISION" and .control_input.upper_decision=="FIXED_POINT"' "$evaluation" >/dev/null
    ;;
  unrecognized-decision)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="UNRECOGNIZED_UPPER_DECISION" and .control_input.upper_decision=="MYSTERY"' "$evaluation" >/dev/null
    ;;
  mixed)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:5,unknown:1,refuted:6,direct_missing:0,stale:1,ambiguous:0,unbounded:0,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="OBSERVED_REVISION_COUNTEREXAMPLE" and ([.cells[]|select(.state=="UNKNOWN" and .unknown_class=="STALE")]|length)==1' "$evaluation" >/dev/null
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 64
    ;;
esac

jq -S -n \
  --arg scenario "$scenario" \
  --arg subject_sha "$(jq -r '.subject_sha' "$evaluation")" \
  --argjson verified_files "$verified" \
  --slurpfile evaluation "$evaluation" \
  '{schema:"gooo/evidence-generator/counterexample-guided-revision/conformance/v1",decision:"CONFORMANT",
    scenario:$scenario,subject_sha:$subject_sha,manifest:{verified:$verified_files,total:6},
    process:$evaluation[0].summary,claim:$evaluation[0].claim,input_claim_promoted:$evaluation[0].input_claim_promoted,
    proposal_status:$evaluation[0].proposal_status,improvement:$evaluation[0].improvement_claim}' > "$report"
