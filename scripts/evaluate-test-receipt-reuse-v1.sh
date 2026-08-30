#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 9 ]; then
  echo "usage: evaluate-test-receipt-reuse-v1.sh REPOSITORY DENOMINATOR CURRENT_SCOPE RECEIPT RESULT ACTIVITY_RESOLUTION OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
denominator=$2
current_scope=$3
receipt=$4
result=$5
activity_resolution=$6
output=$7
subject_sha=$8
scenario=$9

for input in "$denominator" "$current_scope" "$activity_resolution"; do
  test -f "$input"
done

repository_real=$(realpath "$repository")
if [ -d "$output" ] && find "$output" -mindepth 1 -print -quit | grep -q .; then
  echo "output directory must be empty" >&2
  exit 65
fi
mkdir -p "$output"
output_real=$(realpath "$output")
if [ "$output_real" = "$repository_real" ] || [[ "$output_real" == "$repository_real/"* ]]; then
  echo "output directory must be outside the source repository" >&2
  exit 65
fi

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

jq -e '.schema=="gooo/evidence-generator/test-receipt-reuse-denominator/v1" and .target_cells==12 and (.cells|length)==12 and ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12' "$denominator" >/dev/null
jq -e '([.proof_totals[].total]|add)==12 and all(.proof_totals[];.total==4) and ([.indicator_totals[].total]|add)==12 and all(.indicator_totals[];.total==4)' "$denominator" >/dev/null
jq -e '.schema=="gooo/evidence-generator/test-scope/v1" and (.scope.files|length)==1 and (.scope.command|length)==5' "$current_scope" >/dev/null
jq -e '.activity_resolution_observation.summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12}' "$activity_resolution" >/dev/null

current_scope_digest=$(json_digest "$current_scope")
activity_resolution_digest=$(json_digest "$activity_resolution")
receipt_present=false
receipt_digest=MISSING
result_present=false
result_digest=MISSING
receipt_schema_valid=false
receipt_decision=MISSING
receipt_semantic_hash=MISSING
actual_semantic_hash=MISSING
receipt_result_digest=MISSING
producer_test_executions=0
producer_wall_ms=0
producer_peak_rss_kib=0
receipt_repository_writes=0
receipt_source_mutations=0
receipt_local_tests=0

if [ -f "$receipt" ]; then
  receipt_present=true
  receipt_digest=$(json_digest "$receipt")
  if jq -e '.schema=="gooo/evidence-generator/test-receipt/v1"' "$receipt" >/dev/null 2>&1; then
    receipt_schema_valid=true
  fi
  receipt_decision=$(jq -r '.result.decision // "MISSING"' "$receipt" 2>/dev/null || echo MISSING)
  receipt_semantic_hash=$(jq -r '.result.semantic_hash // "MISSING"' "$receipt" 2>/dev/null || echo MISSING)
  receipt_result_digest=$(jq -r '.result.output_sha256 // "MISSING"' "$receipt" 2>/dev/null || echo MISSING)
  producer_test_executions=$(jq -r '.execution.test_executions // 0' "$receipt" 2>/dev/null || echo 0)
  producer_wall_ms=$(jq -r '.execution.wall_ms // 0' "$receipt" 2>/dev/null || echo 0)
  producer_peak_rss_kib=$(jq -r '.execution.peak_rss_kib // 0' "$receipt" 2>/dev/null || echo 0)
  receipt_repository_writes=$(jq -r '.authority.repository_writes // 0' "$receipt" 2>/dev/null || echo 0)
  receipt_source_mutations=$(jq -r '.authority.source_mutations // 0' "$receipt" 2>/dev/null || echo 0)
  receipt_local_tests=$(jq -r '.authority.local_test_executions // 0' "$receipt" 2>/dev/null || echo 0)
fi

if [ -f "$result" ]; then
  result_present=true
  result_digest=$(sha256sum "$result" | awk '{print $1}')
  actual_semantic_hash=$(jq -r '.semantic_hash // "MISSING"' "$result" 2>/dev/null || echo MISSING)
fi

scope_present=false
scope_match=false
if [ "$receipt_present" = true ] && jq -e '.scope|type=="object"' "$receipt" >/dev/null 2>&1; then
  scope_present=true
  current_scope_value=$(jq -S -c '.scope' "$current_scope")
  receipt_scope_value=$(jq -S -c '.scope' "$receipt")
  if [ "$current_scope_value" = "$receipt_scope_value" ]; then scope_match=true; fi
fi

jq -S -n \
  --arg current_scope_digest "$current_scope_digest" \
  --arg receipt_digest "$receipt_digest" \
  --arg result_digest "$result_digest" \
  --arg resolution_digest "$activity_resolution_digest" \
  --arg receipt_decision "$receipt_decision" \
  --arg receipt_semantic_hash "$receipt_semantic_hash" \
  --arg actual_semantic_hash "$actual_semantic_hash" \
  --arg receipt_result_digest "$receipt_result_digest" \
  --argjson receipt_present "$receipt_present" \
  --argjson result_present "$result_present" \
  --argjson receipt_schema_valid "$receipt_schema_valid" \
  --argjson scope_present "$scope_present" \
  --argjson scope_match "$scope_match" \
  --argjson producer_test_executions "$producer_test_executions" \
  --argjson producer_wall_ms "$producer_wall_ms" \
  --argjson producer_peak_rss_kib "$producer_peak_rss_kib" \
  --argjson receipt_repository_writes "$receipt_repository_writes" \
  --argjson receipt_source_mutations "$receipt_source_mutations" \
  --argjson receipt_local_tests "$receipt_local_tests" '
  {
    schema:"gooo/evidence-generator/test-receipt-observation/v1",
    input_digests:{current_scope:$current_scope_digest,receipt:$receipt_digest,result:$result_digest,activity_resolution:$resolution_digest},
    receipt:{present:$receipt_present,schema_valid:$receipt_schema_valid,decision:$receipt_decision,
      semantic_hash:$receipt_semantic_hash,result_digest:$receipt_result_digest},
    result:{present:$result_present,semantic_hash:$actual_semantic_hash,digest:$result_digest},
    scope:{present:$scope_present,match:$scope_match},
    producer_execution:{test_executions:$producer_test_executions,wall_ms:$producer_wall_ms,peak_rss_kib:$producer_peak_rss_kib},
    receipt_authority:{repository_writes:$receipt_repository_writes,source_mutations:$receipt_source_mutations,local_test_executions:$receipt_local_tests}
  }
' > "$output_real/input-observation.json"

overrides='[]'
append_override() {
  local item=$1
  overrides=$(jq -c --argjson item "$item" '. + [$item]' <<<"$overrides")
}

if [ "$receipt_present" != true ]; then
  append_override "$(jq -n '{cell_id:"BASELINE_TEST_EXECUTION",state:"UNKNOWN",stage:"EXECUTION",step:"RECORD_BASELINE_TEST_EXECUTION",reason:"TEST_RECEIPT_MISSING",unknown_class:"DIRECT_MISSING",next_operation:"PROVIDE_EXACT_TEST_RECEIPT",blocked_by:[]}')"
elif [ "$producer_test_executions" -ne 1 ]; then
  append_override "$(jq -n '{cell_id:"BASELINE_TEST_EXECUTION",state:"REFUTED",stage:"EXECUTION",step:"RECORD_BASELINE_TEST_EXECUTION",reason:"BASELINE_TEST_EXECUTION_COUNT_INVALID",unknown_class:null,next_operation:"RECORD_EXACTLY_ONE_BASELINE_TEST_EXECUTION",blocked_by:[]}')"
fi

if [ "$receipt_present" = true ] && [ "$receipt_schema_valid" != true ]; then
  append_override "$(jq -n '{cell_id:"TEST_RECEIPT",state:"REFUTED",stage:"RECEIPT",step:"PUBLISH_EXACT_TEST_RECEIPT",reason:"TEST_RECEIPT_SCHEMA_MISMATCH",unknown_class:null,next_operation:"RESTORE_TEST_RECEIPT_SCHEMA",blocked_by:[]}')"
fi

if [ "$receipt_present" = true ]; then
  if [ "$receipt_decision" = MISSING ] || [ "$receipt_semantic_hash" = MISSING ] || [ "$receipt_result_digest" = MISSING ] || [ "$result_present" != true ]; then
    append_override "$(jq -n '{cell_id:"RECEIPT_IDENTITY",state:"UNKNOWN",stage:"IDENTITY",step:"VERIFY_TEST_RECEIPT_IDENTITY",reason:"TEST_RECEIPT_RESULT_EVIDENCE_MISSING",unknown_class:"DIRECT_MISSING",next_operation:"RESTORE_TEST_RECEIPT_RESULT_EVIDENCE",blocked_by:[]}')"
  elif [ "$receipt_decision" != PASS ]; then
    append_override "$(jq -n '{cell_id:"RECEIPT_IDENTITY",state:"REFUTED",stage:"IDENTITY",step:"VERIFY_TEST_RECEIPT_IDENTITY",reason:"UNRECOGNIZED_TEST_RECEIPT_DECISION",unknown_class:null,next_operation:"REQUIRE_EXPLICIT_PASS_DECISION",blocked_by:[]}')"
  elif [ "$receipt_result_digest" != "$result_digest" ] || [ "$receipt_semantic_hash" != "$actual_semantic_hash" ] || ! jq -e '.schema_version=="gooo/diagnostics/v1" and .status=="ok"' "$result" >/dev/null 2>&1; then
    append_override "$(jq -n '{cell_id:"RECEIPT_IDENTITY",state:"REFUTED",stage:"IDENTITY",step:"VERIFY_TEST_RECEIPT_IDENTITY",reason:"TEST_RECEIPT_RESULT_CONTRADICTION",unknown_class:null,next_operation:"REGENERATE_TEST_RECEIPT_FROM_RESULT",blocked_by:[]}')"
  fi

  if [ "$scope_present" != true ]; then
    append_override "$(jq -n '{cell_id:"SCOPE_EQUIVALENCE",state:"UNKNOWN",stage:"EQUIVALENCE",step:"COMPARE_TEST_SCOPE_DIGESTS",reason:"TEST_RECEIPT_SCOPE_MISSING",unknown_class:"DIRECT_MISSING",next_operation:"RESTORE_TEST_RECEIPT_SCOPE",blocked_by:[]}')"
  elif [ "$scope_match" != true ]; then
    append_override "$(jq -n '{cell_id:"SCOPE_EQUIVALENCE",state:"REFUTED",stage:"EQUIVALENCE",step:"COMPARE_TEST_SCOPE_DIGESTS",reason:"TEST_RECEIPT_SCOPE_MISMATCH",unknown_class:null,next_operation:"RUN_TEST_FOR_CURRENT_SCOPE",blocked_by:[]}')"
  fi

  if [ "$receipt_repository_writes" -ne 0 ] || [ "$receipt_source_mutations" -ne 0 ] || [ "$receipt_local_tests" -ne 0 ]; then
    append_override "$(jq -n '{cell_id:"EXECUTION_AVOIDANCE",state:"REFUTED",stage:"AUTHORITY",step:"RECORD_RECEIPT_REUSE_WITHOUT_CONSUMER_TEST",reason:"TEST_RECEIPT_AUTHORITY_ESCALATED",unknown_class:null,next_operation:"RESTORE_ZERO_WRITE_TEST_AUTHORITY",blocked_by:[]}')"
  fi
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

jq -S -n --slurpfile denominator "$denominator" --argjson overrides "$overrides" '
  def override_for($id): ([$overrides[]|select(.cell_id==$id)][0] // null);
  (reduce $denominator[0].cells[] as $cell
    ({cells:[],decisions:{}};
      . as $acc |
      (override_for($cell.id)) as $override |
      ([$cell.depends_on[]? as $dependency | $acc.decisions[$dependency]]) as $dependencies |
      (if $override != null then $override
       elif any($dependencies[]; .state=="REFUTED") then
         {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_REFUTED",
          unknown_class:null,next_operation:"RESOLVE_REFUTED_PREDECESSORS",
          blocked_by:[$dependencies[]|select(.state=="REFUTED")|.cell_id]}
       elif any($dependencies[]; .state=="UNKNOWN") then
         {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_BLOCKED",
          unknown_class:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",
          blocked_by:[$dependencies[]|select(.state=="UNKNOWN")|.cell_id]}
       else
         {state:"CLOSED",stage:null,step:null,reason:$cell.closed_reason,
          unknown_class:null,next_operation:"NONE",blocked_by:[]}
       end) as $decision |
      .cells += [$cell + $decision + {cell_id:$cell.id}] |
      .decisions[$cell.id] = ($decision + {cell_id:$cell.id})
    )) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length) as $direct_missing |
  ([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$evaluation.cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")][0] // null) as $first_unknown |
  {
    schema:"gooo/evidence-generator/test-receipt-process/v1",
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "TEST_RECEIPT_REUSE_UNKNOWN" else "TEST_RECEIPT_REUSE_CLOSED" end),
    summary:{total:$denominator[0].target_cells,closed:$closed,unknown:$unknown,refuted:$refuted,
      direct_missing:$direct_missing,dependency_blocked:$dependency_blocked},
    proofs:[$denominator[0].proof_totals[] as $proof | {choice:$proof.proof_choice,total:$proof.total,
      closed:([$evaluation.cells[]|select(.proof_choice==$proof.proof_choice and .state=="CLOSED")]|length)}],
    indicators:[$denominator[0].indicator_totals[] as $indicator | {class:$indicator.indicator_class,total:$indicator.total,
      closed:([$evaluation.cells[]|select(.indicator_class==$indicator.indicator_class and .state=="CLOSED")]|length)}],
    cells:$evaluation.cells,
    claim:(if $first_refuted!=null then
      {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,
       unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by}
    elif $first_unknown!=null then
      {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,
       unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,blocked_by:$first_unknown.blocked_by}
    else
      {state:"CLOSED",stage:null,step:null,reason:"EXACT_TEST_RECEIPT_REUSE_CONFORMED",
       unknown_class:null,next_operation:"PUBLISH_TEST_RECEIPT_REUSE_REPORT",blocked_by:[]}
    end)
  }
' > "$temporary/process.json"

decision=$(jq -r '.decision' "$temporary/process.json")
reuse_observed=0
if [ "$decision" = TEST_RECEIPT_REUSE_CLOSED ]; then reuse_observed=1; fi

jq -S -n \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --arg decision "$decision" \
  --argjson reuse_observed "$reuse_observed" \
  --slurpfile observation "$output_real/input-observation.json" \
  --slurpfile process "$temporary/process.json" '
  {
    schema:"gooo/evidence-generator/test-receipt-reuse-report/v1",
    subject_sha:$subject_sha,
    scenario:$scenario,
    decision:$decision,
    input_digests:$observation[0].input_digests,
    observation:$observation[0],
    summary:$process[0].summary,
    proofs:$process[0].proofs,
    indicators:$process[0].indicators,
    cells:$process[0].cells,
    reuse:{producer_test_executions:$observation[0].producer_execution.test_executions,
      consumer_test_executions:0,receipt_reuses:$reuse_observed,required_receipt_reuses:1,
      exact_scope_pairs:(if $reuse_observed==1 then 1 else 0 end),required_scope_pairs:1},
    authority:{application_root:"CALLER_OWNED_TEMP_ONLY",repository_writes:0,source_mutations:0,
      local_test_executions:0,consumer_test_executions:0,denominator_changes:0,
      receipt_repository_writes:$observation[0].receipt_authority.repository_writes,
      receipt_source_mutations:$observation[0].receipt_authority.source_mutations},
    improvement:{receipt_reuse_without_consumer_execution:{state:(if $reuse_observed==1 then "CLOSED" else $process[0].claim.state end),
        observed:$reuse_observed,required:1},
      saved_test_ms:{state:"UNKNOWN",before:$observation[0].producer_execution.wall_ms,after:null,
        reason:"EQUIVALENT_INDEPENDENT_TIMING_PAIR_ABSENT"},
      generalized_cross_run_consumer:{state:"UNKNOWN",observed:0,required:1,stage:"GENERALIZATION",
        step:"OBSERVE_INDEPENDENT_RELEASE_CONSUMER",reason:"INDEPENDENT_RELEASE_CONSUMER_ABSENT",
        unknown_class:"DIRECT_MISSING",next_operation:"PUBLISH_AND_OBSERVE_ONE_RELEASE_CONSUMER",blocked_by:[]}},
    external_utility:{state:"UNKNOWN",observed:0,required:1,stage:"UTILITY",step:"OBSERVE_EXTERNAL_USER_TEST_REUSE",
      reason:"EXTERNAL_USER_EVIDENCE_ABSENT",unknown_class:"DIRECT_MISSING",
      next_operation:"OBSERVE_ONE_EXTERNAL_USER_SESSION",blocked_by:[]},
    claim:$process[0].claim
  }
' > "$output_real/reuse-report.json"

cat > "$output_real/report.md" <<EOF
# Exact test receipt reuse

- scenario: \`$scenario\`
- decision: \`$decision\`
- cells: \`$(jq -r '.summary.closed' "$temporary/process.json") CLOSED / $(jq -r '.summary.unknown' "$temporary/process.json") UNKNOWN / $(jq -r '.summary.refuted' "$temporary/process.json") REFUTED\`
- producer test executions: \`$producer_test_executions\`
- receipt reuses: \`$reuse_observed/1\`
- consumer test executions: \`0\`
- exact scope match: \`$scope_match\`
- saved test milliseconds: \`UNKNOWN\`
- repository writes: \`0\`
EOF

tracked_files=(input-observation.json reuse-report.json report.md)
entries='[]'
for relative_path in "${tracked_files[@]}"; do
  digest=$(sha256sum "$output_real/$relative_path" | awk '{print $1}')
  size=$(wc -c < "$output_real/$relative_path" | tr -d ' ')
  entries=$(jq -c --arg path "$relative_path" --arg sha256 "$digest" --argjson size "$size" '. + [{path:$path,sha256:$sha256,size_bytes:$size}]' <<<"$entries")
done
jq -S -n --arg subject_sha "$subject_sha" --arg scenario "$scenario" --argjson files "$entries" '
  {schema:"gooo/evidence-generator/test-receipt-reuse-manifest/v1",subject_sha:$subject_sha,
   scenario:$scenario,tracked_file_count:($files|length),files:$files}
' > "$output_real/manifest.json"

test "$(find "$output_real" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
