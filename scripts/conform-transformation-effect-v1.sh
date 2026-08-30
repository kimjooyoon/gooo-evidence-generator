#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "usage: conform-transformation-effect-v1.sh OUTPUT PROCESS_DENOMINATOR TARGET_DENOMINATOR OBSERVATION CANDIDATE BASELINE SCENARIO REPORT" >&2
  exit 64
fi

output=$(realpath "$1")
process_denominator=$2
target_denominator=$3
observation=$4
candidate=$5
baseline=$6
scenario=$7
report=$8

expected_files=(
  activity-bindings.json
  after-evaluation.json
  after-project.json
  before-evaluation.json
  before-project.json
  candidate-selection.json
  effect-receipt.json
  manifest.json
  report.md
)
test "$(find "$output" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 9
for relative_path in "${expected_files[@]}"; do test -f "$output/$relative_path"; done

manifest="$output/manifest.json"
receipt="$output/effect-receipt.json"
jq -e '.schema=="gooo/evidence-generator/transformation-manifest/v1" and .tracked_file_count==8 and (.files|length)==8' "$manifest" >/dev/null

verified=0
while IFS=$'\t' read -r relative_path expected_digest expected_size; do
  case "$relative_path" in
    /*|*..*) exit 65 ;;
  esac
  actual_digest=$(sha256sum "$output/$relative_path" | awk '{print $1}')
  actual_size=$(wc -c < "$output/$relative_path" | tr -d ' ')
  test "$actual_digest" = "$expected_digest"
  test "$actual_size" -eq "$expected_size"
  verified=$((verified+1))
done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
test "$verified" -eq 8

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

process_denominator_digest=$(json_digest "$process_denominator")
target_denominator_digest=$(json_digest "$target_denominator")
observation_digest=$(json_digest "$observation")
candidate_digest=$(json_digest "$candidate")
baseline_digest=$(json_digest "$baseline")

jq -e \
  --arg process_denominator "$process_denominator_digest" \
  --arg target_denominator "$target_denominator_digest" \
  --arg observation "$observation_digest" \
  --arg candidate "$candidate_digest" \
  --arg baseline "$baseline_digest" \
  --arg scenario "$scenario" '
  .schema=="gooo/evidence-generator/transformation-effect-receipt/v1" and
  .scenario==$scenario and
  .input_digests.process_denominator==$process_denominator and
  .input_digests.target_denominator==$target_denominator and
  .input_digests.observation==$observation and
  .input_digests.candidate==$candidate and
  .input_digests.baseline==$baseline and
  .authority.repository_writes==0 and .authority.denominator_changes==0 and
  .authority.local_test_executions==0 and .authority.go_build_executions==0 and
  .authority.go_test_executions==0 and
  .external_utility.state=="UNKNOWN" and .external_utility.evidence==0 and
  .external_utility.required==1 and
  (.external_utility|has("stage") and has("step") and has("reason") and
    has("unknown_class") and has("next_operation") and has("blocked_by"))
' "$receipt" >/dev/null

cmp -s <(jq -S . "$baseline") "$output/before-project.json"

recompute_summary() {
  local project=$1
  jq -c '{total:(.cells|length),closed:([.cells[]|select(.state=="CLOSED")]|length),unknown:([.cells[]|select(.state=="UNKNOWN")]|length),refuted:([.cells[]|select(.state=="REFUTED")]|length),unknown_with_six_fields:([.cells[]|select(.state=="UNKNOWN" and (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and (.unknown_class|type)=="string" and (.next_operation|type)=="string" and (.blocked_by|type)=="array")]|length)}' "$project"
}

before_summary=$(recompute_summary "$output/before-project.json")
after_summary=$(recompute_summary "$output/after-project.json")
jq -e --argjson expected "$before_summary" '.summary==$expected and .denominator_identity_match and .cell_count_match and .cell_ids_match and .summary.unknown_with_six_fields==.summary.unknown' "$output/before-evaluation.json" >/dev/null
jq -e --argjson expected "$after_summary" '.summary==$expected and .denominator_identity_match and .cell_count_match and .cell_ids_match and .summary.unknown_with_six_fields==.summary.unknown' "$output/after-evaluation.json" >/dev/null

before_unrelated=$(jq -S -c '{schema,denominator_id,subject_id,repository_writes,local_test_executions,cells:[.cells[]|select(.id!="UNKNOWN_TRACE")]}' "$output/before-project.json" | sha256sum | awk '{print $1}')
after_unrelated=$(jq -S -c '{schema,denominator_id,subject_id,repository_writes,local_test_executions,cells:[.cells[]|select(.id!="UNKNOWN_TRACE")]}' "$output/after-project.json" | sha256sum | awk '{print $1}')
test "$before_unrelated" = "$after_unrelated"
jq -e --arg before "$before_unrelated" --arg after "$after_unrelated" '.effect.unrelated_before_digest==$before and .effect.unrelated_after_digest==$after and .effect.unrelated_cell_changes==0 and .effect.internal_replay_equal==true' "$receipt" >/dev/null

jq -e --slurpfile denominator "$process_denominator" '
  . as $receipt |
  $receipt.process.summary.total==12 and
  $receipt.process.summary.closed==([$receipt.process.cells[]|select(.state=="CLOSED")]|length) and
  $receipt.process.summary.unknown==([$receipt.process.cells[]|select(.state=="UNKNOWN")]|length) and
  $receipt.process.summary.refuted==([$receipt.process.cells[]|select(.state=="REFUTED")]|length) and
  all($receipt.process.cells[]|select(.state=="UNKNOWN");
    (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
    (.unknown_class|type)=="string" and (.next_operation|type)=="string" and (.blocked_by|type)=="array") and
  (if $receipt.process.summary.refuted>0 then $receipt.claim.state=="REFUTED"
   elif $receipt.process.summary.unknown>0 then $receipt.claim.state=="UNKNOWN"
   else $receipt.claim.state=="CLOSED" end) and
  all($denominator[0].proof_totals[];
    . as $proof |
    ([$receipt.process.cells[]|select(.proof_choice==$proof.proof_choice)]|length)==$proof.total) and
  all($denominator[0].indicator_totals[];
    . as $indicator |
    ([$receipt.process.cells[]|select(.indicator_class==$indicator.indicator_class)]|length)==$indicator.total)
' "$receipt" >/dev/null

case "$scenario" in
  normal)
    jq -e '
      .decision=="TRANSFORMATION_EFFECT_CLOSED" and
      .process.summary=={total:12,closed:12,unknown:0,refuted:0,direct_missing:0,dependency_blocked:0} and
      .candidate_selection.state=="CLOSED" and .candidate_selection.support=={minimum:3,expected:4,observed:4,total:4} and
      .effect.before.total==12 and .effect.before.closed==11 and .effect.before.unknown==1 and .effect.before.refuted==0 and
      .effect.after.total==12 and .effect.after.closed==12 and .effect.after.unknown==0 and .effect.after.refuted==0 and
      .effect.delta=={total:0,closed:1,unknown:-1,refuted:0} and .effect.target_cell_transitions==1 and
      .improvement.state=="CLOSED" and .improvement.exact_pairs=={required:1,observed:1} and
      .improvement.generalized_language_improvement.state=="UNKNOWN"
    ' "$receipt" >/dev/null
    jq -e '.cells[]|select(.id=="UNKNOWN_TRACE")|.state=="CLOSED" and .reason=="META_BOUND_EXPLICIT_UNKNOWN_PATTERN_APPLIED"' "$output/after-project.json" >/dev/null
    ;;
  missing-pattern)
    jq -e '
      .decision=="INCOMPLETE" and
      .process.summary=={total:12,closed:5,unknown:7,refuted:0,direct_missing:1,dependency_blocked:6} and
      .claim.state=="UNKNOWN" and .claim.reason=="CANDIDATE_PATTERN_OBSERVATION_MISSING" and
      .claim.unknown_class=="DIRECT_MISSING" and .claim.blocked_by==[] and
      .improvement.state=="UNKNOWN" and .improvement.exact_pairs=={required:1,observed:0}
    ' "$receipt" >/dev/null
    cmp -s "$output/before-project.json" "$output/after-project.json"
    ;;
  unauthorized-operation)
    jq -e '
      .decision=="FAIL_CLOSED" and
      .process.summary=={total:12,closed:6,unknown:0,refuted:6,direct_missing:0,dependency_blocked:0} and
      .claim.state=="REFUTED" and .claim.reason=="UNAUTHORIZED_TRANSFORMATION_OPERATION" and
      .improvement.state=="REFUTED"
    ' "$receipt" >/dev/null
    cmp -s "$output/before-project.json" "$output/after-project.json"
    ;;
  refuted-over-unknown)
    jq -e '
      . as $receipt |
      .decision=="FAIL_CLOSED" and
      .process.summary=={total:12,closed:4,unknown:2,refuted:6,direct_missing:1,dependency_blocked:1} and
      .claim.state=="REFUTED" and .claim.reason=="BASELINE_COUNTEREXAMPLE_PRESENT" and
      ([$receipt.process.cells[]|select(.id=="PATTERN_OBSERVATION" and .state=="UNKNOWN")]|length)==1
    ' "$receipt" >/dev/null
    cmp -s "$output/before-project.json" "$output/after-project.json"
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 64
    ;;
esac

jq -S -n \
  --arg scenario "$scenario" \
  --arg subject_sha "$(jq -r '.subject_sha' "$receipt")" \
  --argjson verified_files "$verified" \
  --slurpfile receipt "$receipt" '
  {
    schema:"gooo/evidence-generator/transformation-conformance/v1",
    decision:"CONFORMANT",
    scenario:$scenario,
    subject_sha:$subject_sha,
    manifest:{verified:$verified_files,total:8},
    process:$receipt[0].process.summary,
    effect:$receipt[0].effect,
    claim:$receipt[0].claim
  }
' > "$report"
