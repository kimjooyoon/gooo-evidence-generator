#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 9 ]; then
  echo "usage: evaluate-counterexample-guided-revision-v1.sh REPOSITORY DENOMINATOR CLAIM PROPOSAL EVIDENCE ACTIVITY_RESOLUTION OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
denominator=$2
claim=$3
proposal=$4
evidence=$5
activity_resolution=$6
output=$7
subject_sha=$8
scenario=$9

for input in "$denominator" "$claim" "$proposal" "$evidence" "$activity_resolution"; do
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

denominator_digest=$(json_digest "$denominator")
claim_digest=$(json_digest "$claim")
proposal_digest=$(json_digest "$proposal")
evidence_digest=$(json_digest "$evidence")
activity_resolution_digest=$(json_digest "$activity_resolution")

jq -e '
  .schema=="gooo/evidence-generator/counterexample-guided-revision-denominator/v1" and
  .target_cells==12 and (.cells|length)==12 and ([.cells[].id]|unique|length)==12 and
  ([.cells[].activity]|unique|length)==12 and
  ([.cells[]|select(.proof_choice=="FOUNDATION")]|length)==4 and
  ([.cells[]|select(.proof_choice=="COHERENCE")]|length)==4 and
  ([.cells[]|select(.proof_choice=="REGRESSION")]|length)==4 and
  ([.cells[]|select(.indicator_class=="DRIVER")]|length)==4 and
  ([.cells[]|select(.indicator_class=="OUTCOME")]|length)==4 and
  ([.cells[]|select(.indicator_class=="GUARDRAIL")]|length)==4 and
  ([.cells[].ordinal]|sort)==[range(1;13)]
' "$denominator" >/dev/null
jq -e '.activity_resolution_observation.summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12}' "$activity_resolution" >/dev/null

claim_valid=false
if jq -e '
  .schema=="gooo/evidence-generator/counterexample-guided-revision/claim/v1" and
  .state=="UNKNOWN" and .resolution=="HIGH" and
  .stage=="CLAIM" and .step=="OBSERVE_INPUT_CLAIM" and
  .unknown_class=="UNBOUNDED" and (.blocked_by|type)=="array" and
  (.scope.changed_paths==["resolution"])
' "$claim" >/dev/null 2>&1; then
  claim_valid=true
fi

claim_id=$(jq -r '.id // "__MISSING__"' "$claim" 2>/dev/null || echo __MISSING__)

proposal_valid=false
if jq -e --arg claim_id "$claim_id" '
  .schema=="gooo/evidence-generator/counterexample-guided-revision-proposal/v1" and
  .target_claim_id==$claim_id and
  .operation=="LOWER_RESOLUTION_ONLY" and .from_resolution=="HIGH" and
  .to_resolution=="MEDIUM" and .changed_paths==["resolution"] and
  .unrelated_changes==0 and .repository_writes==0 and .source_mutations==0 and
  .exact_before_after.available==false and .improvement_claim.state=="UNKNOWN"
' "$proposal" >/dev/null 2>&1; then
  proposal_valid=true
fi

evidence_valid=false
if jq -e --arg claim_id "$claim_id" '
  .schema=="gooo/evidence-generator/counterexample-guided-revision/evidence/v1" and
  (.claim_id|type)=="string" and .claim_id==$claim_id and (.observation|type)=="object" and
  (.counterexample|type)=="object"
' "$evidence" >/dev/null 2>&1; then
  evidence_valid=true
fi

upper_decision=$(jq -r '.upper_decision // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
claim_present=$(jq -r '.observation.claim_present // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
subject_present=$(jq -r '.observation.subject_present // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
frontier_bounded=$(jq -r '.observation.frontier_bounded // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
scope_unambiguous=$(jq -r '.observation.scope_unambiguous // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
fresh=$(jq -r '.observation.fresh // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
dependency_state=$(jq -r '.observation.dependencies[0].state // "__MISSING__"' "$evidence" 2>/dev/null || echo __MISSING__)
dependency_id=$(jq -r '.observation.dependencies[0].id // "UPSTREAM_DECISION"' "$evidence" 2>/dev/null || echo UPSTREAM_DECISION)
counterexample_present=$(jq -r '.counterexample.present // false' "$evidence" 2>/dev/null || echo false)
counterexample_kind=$(jq -r '.counterexample.kind // "NONE"' "$evidence" 2>/dev/null || echo NONE)

overrides='[]'
append_override() {
  local item=$1
  overrides=$(jq -c --argjson item "$item" '. + [$item]' <<<"$overrides")
}

decision_json() {
  local cell_id=$1
  local state=$2
  local stage=$3
  local step=$4
  local reason=$5
  local unknown_class=$6
  local next_operation=$7
  local blocked_by=$8
  local priority=$9
  jq -n \
    --arg cell_id "$cell_id" --arg state "$state" --arg stage "$stage" --arg step "$step" \
    --arg reason "$reason" --arg unknown_class "$unknown_class" \
    --arg next_operation "$next_operation" --argjson blocked_by "$blocked_by" \
    --argjson priority "$priority" \
    '{cell_id:$cell_id,state:$state,stage:$stage,step:$step,reason:$reason,
      unknown_class:(if $unknown_class=="" then null else $unknown_class end),
      next_operation:$next_operation,blocked_by:$blocked_by,
      frontier:[{stage:$stage,step:$step}],priority:$priority}'
}

if [ "$counterexample_present" = true ]; then
  append_override "$(decision_json COUNTEREXAMPLE_RECEIPT REFUTED COUNTEREXAMPLE OBSERVE_REVISION_COUNTEREXAMPLE OBSERVED_REVISION_COUNTEREXAMPLE '' REJECT_REVISION_PROPOSAL '[]' 100)"
elif [ "$evidence_valid" != true ]; then
  append_override "$(decision_json CAUSAL_FRONTIER REFUTED INPUT VALIDATE_REVISION_EVIDENCE MALFORMED_REVISION_EVIDENCE '' RESTORE_REVISION_EVIDENCE '[]' 95)"
elif [ "$claim_valid" != true ]; then
  append_override "$(decision_json CLAIM_INPUT REFUTED CLAIM VALIDATE_INPUT_CLAIM MALFORMED_INPUT_CLAIM '' RESTORE_UNKNOWN_INPUT_CLAIM '[]' 94)"
elif [ "$proposal_valid" != true ]; then
  append_override "$(decision_json REVISION_SCOPE REFUTED BOUNDARY VALIDATE_REVISION_SCOPE INVALID_MINIMAL_REVISION_PROPOSAL '' RESTORE_RESOLUTION_ONLY_PROPOSAL '[]' 93)"
elif [ "$upper_decision" != CLOSED ]; then
  if [ "$upper_decision" = FIXED_POINT ]; then
    reason=FIXED_POINT_UPPER_DECISION
  else
    reason=UNRECOGNIZED_UPPER_DECISION
  fi
  append_override "$(decision_json CAUSAL_FRONTIER REFUTED CONTROL VALIDATE_UPPER_DECISION "$reason" '' RESTORE_EXPLICIT_UPPER_DECISION '[]' 92)"
elif [ "$claim_present" != true ] || [ "$subject_present" != true ]; then
  append_override "$(decision_json CLAIM_INPUT UNKNOWN EVIDENCE OBSERVE_INPUT_CLAIM REVISION_INPUT_EVIDENCE_MISSING DIRECT_MISSING PROVIDE_REVISION_INPUT_EVIDENCE '[]' 60)"
elif [ "$dependency_state" = REFUTED ]; then
  append_override "$(decision_json CLAIM_INPUT REFUTED DEPENDENCY RESOLVE_UPSTREAM_DECISION UPSTREAM_DECISION_REFUTED '' RESOLVE_REFUTED_UPSTREAM_DECISION "[\"$dependency_id\"]" 91)"
elif [ "$dependency_state" != CLOSED ]; then
  append_override "$(decision_json CLAIM_INPUT UNKNOWN DEPENDENCY RESOLVE_UPSTREAM_DECISION UPSTREAM_DECISION_UNAVAILABLE DEPENDENCY_BLOCKED RESOLVE_UPSTREAM_DECISION "[\"$dependency_id\"]" 59)"
elif [ "$fresh" != true ]; then
  append_override "$(decision_json CAUSAL_FRONTIER UNKNOWN FRESHNESS VERIFY_EVIDENCE_FRESHNESS REVISION_EVIDENCE_STALE STALE REFRESH_REVISION_EVIDENCE '[]' 58)"
elif [ "$scope_unambiguous" != true ]; then
  append_override "$(decision_json REVISION_SCOPE UNKNOWN BOUNDARY DISAMBIGUATE_REVISION_BOUNDARY REVISION_SCOPE_AMBIGUOUS AMBIGUOUS DISAMBIGUATE_REVISION_SCOPE '[]' 57)"
elif [ "$frontier_bounded" != true ]; then
  append_override "$(decision_json REVISION_SCOPE UNKNOWN BOUNDARY BOUND_REVISION_SCOPE REVISION_SCOPE_UNBOUNDED UNBOUNDED BOUND_REVISION_TO_ONE_RESOLUTION_FIELD '[]' 56)"
fi

# A known counterexample does not erase an independent UNKNOWN frontier. The
# refutation still wins the top-level decision, while the stale coordinate is
# retained for the human repair dossier.
if [ "$counterexample_present" = true ] && [ "$evidence_valid" = true ] &&
   [ "$claim_valid" = true ] && [ "$proposal_valid" = true ] &&
   [ "$upper_decision" = CLOSED ] && [ "$fresh" != true ]; then
  append_override "$(decision_json CAUSAL_FRONTIER UNKNOWN FRESHNESS VERIFY_EVIDENCE_FRESHNESS REVISION_EVIDENCE_STALE STALE REFRESH_REVISION_EVIDENCE '[]' 58)"
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

jq -S -n \
  --slurpfile denominator "$denominator" \
  --argjson overrides "$overrides" \
  --arg dependency_id "$dependency_id" \
  --arg claim_present "$claim_present" \
  --arg subject_present "$subject_present" \
  --argjson claim_valid "$claim_valid" \
  --argjson proposal_valid "$proposal_valid" \
  --argjson evidence_valid "$evidence_valid" \
  --arg upper_decision "$upper_decision" \
  --arg counterexample_kind "$counterexample_kind" '
  def override_for($id): ([$overrides[]|select(.cell_id==$id)][0] // null);
  def clean($decision): ($decision | del(.priority));
  (reduce $denominator[0].cells[] as $cell
    ({cells:[],decisions:{}};
      . as $acc |
      (override_for($cell.id)) as $override |
      ([$cell.depends_on[]? as $dependency | $acc.decisions[$dependency]]) as $dependencies |
      (if any($dependencies[]?; .state=="REFUTED") then
         {state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_REFUTED",
          unknown_class:null,next_operation:"RESOLVE_REFUTED_PREDECESSORS",
          blocked_by:[$dependencies[]|select(.state=="REFUTED")|.cell_id],
          frontier:[{stage:$cell.stage,step:$cell.step}],priority:50}
       elif $override != null and $override.state=="REFUTED" then $override
       elif $override != null then $override
       elif any($dependencies[]?; .state=="UNKNOWN") then
         {state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_BLOCKED",
          unknown_class:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",
          blocked_by:[$dependencies[]|select(.state=="UNKNOWN")|.cell_id],
          frontier:[{stage:$cell.stage,step:$cell.step}],priority:10}
       else
         {state:"CLOSED",stage:null,step:null,reason:$cell.closed_reason,
          unknown_class:null,next_operation:"NONE",blocked_by:[],frontier:[],priority:0}
       end) as $decision |
      .cells += [$cell + (clean($decision)) + {cell_id:$cell.id}] |
      .decisions[$cell.id] = ($decision + {cell_id:$cell.id})
    )) as $evaluation |
  ([$evaluation.cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$evaluation.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$evaluation.cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$evaluation.cells[]|select(.unknown_class=="DIRECT_MISSING")]|length) as $direct_missing |
  ([$evaluation.cells[]|select(.unknown_class=="STALE")]|length) as $stale |
  ([$evaluation.cells[]|select(.unknown_class=="AMBIGUOUS")]|length) as $ambiguous |
  ([$evaluation.cells[]|select(.unknown_class=="UNBOUNDED")]|length) as $unbounded |
  ([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$evaluation.decisions[]|select(.state=="REFUTED")]|if length==0 then null else max_by(.priority) end) as $first_refuted |
  ([$evaluation.decisions[]|select(.state=="UNKNOWN")]|if length==0 then null else max_by(.priority) end) as $first_unknown |
  {
    schema:"gooo/evidence-generator/counterexample-guided-revision/evaluation/v1",
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "REVISION_PROPOSAL_UNKNOWN" else "REVISION_PROPOSAL_CLOSED" end),
    summary:{total:$denominator[0].target_cells,closed:$closed,unknown:$unknown,refuted:$refuted,
      direct_missing:$direct_missing,stale:$stale,ambiguous:$ambiguous,unbounded:$unbounded,
      dependency_blocked:$dependency_blocked},
    cells:$evaluation.cells,
    control_input:{claim_valid:$claim_valid,proposal_valid:$proposal_valid,evidence_valid:$evidence_valid,
      upper_decision:$upper_decision,counterexample_kind:$counterexample_kind,
      claim_present:$claim_present,subject_present:$subject_present,dependency_id:$dependency_id},
    claim:(if $first_refuted!=null then
      {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,
       unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by,
       frontier:$first_refuted.frontier}
    elif $first_unknown!=null then
      {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,
       unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,
       blocked_by:$first_unknown.blocked_by,frontier:$first_unknown.frontier}
    else
      {state:"UNKNOWN",stage:"CLAIM",step:"PRESERVE_INPUT_CLAIM",reason:"INPUT_CLAIM_NOT_PROMOTED",
       unknown_class:"UNBOUNDED",next_operation:"EVALUATE_EXACT_BEFORE_AFTER_PAIR",blocked_by:[],
       frontier:[{stage:"CLAIM",step:"PRESERVE_INPUT_CLAIM"}]}
    end),
    input_claim_promoted:false,
    proposal_status:(if $refuted>0 then "REFUTED" elif $unknown>0 then "UNKNOWN" else "CLOSED" end),
    improvement_claim:{state:"UNKNOWN",reason:"EXACT_BEFORE_AFTER_PAIR_ABSENT",unknown_class:"DIRECT_MISSING",
      next_operation:"PROVIDE_EXACT_BEFORE_AFTER_PAIR",blocked_by:[]},
    authority:{application_root:"CALLER_OWNED_TEMP_ONLY",repository_writes:0,source_mutations:0,
      denominator_changes:0,automatic_claim_promotion:false,local_test_executions:0}
  }
' > "$temporary/evaluation.json"

jq -S -n \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --arg denominator_digest "$denominator_digest" \
  --arg claim_digest "$claim_digest" \
  --arg proposal_digest "$proposal_digest" \
  --arg evidence_digest "$evidence_digest" \
  --arg activity_resolution_digest "$activity_resolution_digest" \
  --slurpfile claim "$claim" \
  --slurpfile proposal "$proposal" \
  --slurpfile evaluation "$temporary/evaluation.json" '
  {
    schema:"gooo/evidence-generator/counterexample-guided-revision/revision-proposal/v1",
    subject_sha:$subject_sha,scenario:$scenario,
    decision:$evaluation[0].proposal_status,
    target_claim_id:($claim[0].id // null),
    input_claim:$claim[0],
    input_claim_after:$claim[0],
    input_claim_promoted:false,
    input_claim_state_before:$claim[0].state,
    input_claim_state_after:$claim[0].state,
    proposed_change:{operation:($proposal[0].operation // null),from_resolution:($proposal[0].from_resolution // null),
      to_resolution:($proposal[0].to_resolution // null),changed_paths:($proposal[0].changed_paths // []),
      applied:false,unrelated_changes:0},
    causal_boundary:$evaluation[0].claim,
    exact_before_after:{available:false,before:null,after:null},
    improvement_claim:$evaluation[0].improvement_claim,
    authority:$evaluation[0].authority,
    input_digests:{denominator:$denominator_digest,claim:$claim_digest,proposal:$proposal_digest,
      evidence:$evidence_digest,activity_resolution:$activity_resolution_digest}
  }
' > "$output_real/revision-proposal.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg evidence_digest "$evidence_digest" \
  --slurpfile evaluation "$temporary/evaluation.json" \
  --slurpfile counterexample "$evidence" '
  {
    schema:"gooo/evidence-generator/counterexample-guided-revision/causal-frontier/v1",
    subject_sha:$subject_sha,scenario:$scenario,state:$evaluation[0].claim.state,
    precedence:"REFUTED_OVER_UNKNOWN",
    claim:$evaluation[0].claim,
    minimal:true,
    frontier:([({cell_id:"CLAIM_BOUNDARY"} + $evaluation[0].claim)] + [$evaluation[0].cells[]|select(.state!="CLOSED")|{
      cell_id,stage,step,state,reason,unknown_class,next_operation,blocked_by,frontier
    }]),
    counterexample_input_digest:$evidence_digest,
    counterexample_present:($counterexample[0].counterexample.present // false)
  }
' > "$output_real/causal-frontier.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg evidence_digest "$evidence_digest" \
  --slurpfile evidence "$evidence" \
  --slurpfile evaluation "$temporary/evaluation.json" '
  ($evidence[0].counterexample // {}) as $input |
  {
    schema:"gooo/evidence-generator/counterexample-guided-revision/counterexample/v1",
    subject_sha:$subject_sha,scenario:$scenario,
    state:(if ($input.present // false) then "REFUTED" else "ABSENT" end),
    present:($input.present // false),
    kind:($input.kind // "NONE"),
    expected:($input.expected // null),
    observed:($input.observed // null),
    input_digest:$evidence_digest,
    partial_output:0,
    decision_precedence:(if $evaluation[0].summary.refuted>0 then "REFUTED" else $evaluation[0].claim.state end),
    source_mutation:0
  }
' > "$output_real/counterexample.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg denominator_digest "$denominator_digest" \
  --arg claim_digest "$claim_digest" \
  --arg proposal_digest "$proposal_digest" \
  --arg evidence_digest "$evidence_digest" \
  --arg activity_resolution_digest "$activity_resolution_digest" \
  --slurpfile evaluation "$temporary/evaluation.json" \
  '$evaluation[0] + {subject_sha:$subject_sha,scenario:$scenario,
    input_digests:{denominator:$denominator_digest,claim:$claim_digest,proposal:$proposal_digest,
      evidence:$evidence_digest,activity_resolution:$activity_resolution_digest}}' \
  > "$output_real/evaluation.json"
jq -S --arg subject_sha "$subject_sha" --arg source_digest "$activity_resolution_digest" '
  {schema:"gooo/evidence-generator/counterexample-guided-revision/activity-bindings/v1",
   subject_sha:$subject_sha,source_digest:$source_digest,
   core_release:.activity_resolution_observation.core_release,
   summary:.activity_resolution_observation.summary,
   bindings:[.activity_resolution_observation.entries[]|{ordinal,id,activity,receipt:.receipt}]}
' "$activity_resolution" > "$output_real/activity-bindings.json"

decision=$(jq -r '.decision' "$temporary/evaluation.json")
claim_state=$(jq -r '.claim.state' "$temporary/evaluation.json")
claim_reason=$(jq -r '.claim.reason' "$temporary/evaluation.json")
claim_class=$(jq -r '.claim.unknown_class // "NONE"' "$temporary/evaluation.json")
claim_stage=$(jq -r '.claim.stage' "$temporary/evaluation.json")
claim_step=$(jq -r '.claim.step' "$temporary/evaluation.json")
claim_blocked_by=$(jq -c '.claim.blocked_by' "$temporary/evaluation.json")
claim_frontier=$(jq -c '.claim.frontier' "$temporary/evaluation.json")
cat > "$output_real/human-dossier.md" <<EOF
# Counterexample-guided revision dossier

- scenario: \`$scenario\`
- evaluator decision: \`$decision\`
- causal claim state: \`$claim_state\`
- causal frontier: \`$claim_stage/$claim_step\` \`$claim_reason\` (\`$claim_class\`)
- blocked by: \`$claim_blocked_by\`
- frontier coordinates: \`$claim_frontier\`
- proposed operation: \`LOWER_RESOLUTION_ONLY\` (HIGH -> MEDIUM)
- input claim promoted: \`false\`
- exact before/after improvement evidence: \`UNKNOWN\`
- known counterexample partial output: \`0\`
- source mutation: \`0\`
- repository writes: \`0\`
- local test executions: \`0\`

The proposal is caller-owned output only. An UNKNOWN result retains its exact
stage, step, reason, unknown class, next operation, blocked-by set, and frontier.
A known contradiction or malformed control decision is REFUTED and takes
precedence over UNKNOWN. No source claim is promoted to CLOSED by this run.
EOF

tracked_files=(activity-bindings.json causal-frontier.json counterexample.json evaluation.json human-dossier.md revision-proposal.json)
entries='[]'
for relative_path in "${tracked_files[@]}"; do
  digest=$(sha256sum "$output_real/$relative_path" | awk '{print $1}')
  size=$(wc -c < "$output_real/$relative_path" | tr -d ' ')
  entries=$(jq -c --arg path "$relative_path" --arg sha256 "$digest" --argjson size "$size" '. + [{path:$path,sha256:$sha256,size_bytes:$size}]' <<<"$entries")
done
jq -S -n --arg subject_sha "$subject_sha" --arg scenario "$scenario" --argjson files "$entries" '
  {schema:"gooo/evidence-generator/counterexample-guided-revision/manifest/v1",subject_sha:$subject_sha,
   scenario:$scenario,tracked_file_count:($files|length),files:$files}
' > "$output_real/manifest.json"

test "$(find "$output_real" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 8
