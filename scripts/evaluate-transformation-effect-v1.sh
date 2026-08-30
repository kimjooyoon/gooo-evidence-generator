#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 10 ]; then
  echo "usage: evaluate-transformation-effect-v1.sh REPOSITORY PROCESS_DENOMINATOR TARGET_DENOMINATOR OBSERVATION CANDIDATE BASELINE ACTIVITY_RESOLUTION OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
process_denominator=$2
target_denominator=$3
observation=$4
candidate=$5
baseline=$6
activity_resolution=$7
output=$8
subject_sha=$9
scenario=${10}

for input in "$process_denominator" "$target_denominator" "$observation" "$candidate" "$baseline" "$activity_resolution"; do
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

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

jq -e '.schema=="gooo/evidence-generator/transformation-effect-denominator/v1" and .target_cells==12 and (.cells|length)==12 and ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12' "$process_denominator" >/dev/null
jq -e '([.proof_totals[].total]|add)==12 and all(.proof_totals[];.total==4) and ([.indicator_totals[].total]|add)==12 and all(.indicator_totals[];.total==4)' "$process_denominator" >/dev/null
jq -e '.schema=="gooo/evidence-generator/denominator/v1" and .target_cells==12 and (.cells|length)==12' "$target_denominator" >/dev/null
jq -e '.schema=="gooo/evidence-generator/repetition-observation/v1" and .observed_projects==4 and .promotion_threshold==3' "$observation" >/dev/null
jq -e '.schema=="gooo/evidence-generator/transformation-candidate/v1"' "$candidate" >/dev/null
jq -e '.schema=="gooo/evidence-generator/transformation-baseline/v1" and (.cells|length)==12' "$baseline" >/dev/null
jq -e '.activity_resolution_observation.summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12}' "$activity_resolution" >/dev/null

process_denominator_digest=$(json_digest "$process_denominator")
target_denominator_digest=$(json_digest "$target_denominator")
observation_digest=$(json_digest "$observation")
candidate_digest=$(json_digest "$candidate")
baseline_digest=$(json_digest "$baseline")
activity_resolution_digest=$(json_digest "$activity_resolution")

pattern_id=$(jq -r '.selection.pattern_id' "$candidate")
required_meta_activity=$(jq -r '.selection.required_meta_activity' "$candidate")
minimum_support=$(jq -r '.selection.minimum_support' "$candidate")
expected_support=$(jq -r '.selection.expected_support' "$candidate")
support_total=$(jq -r '.selection.support_total' "$candidate")
pattern_count=$(jq --arg id "$pattern_id" '[.patterns[]|select(.id==$id)]|length' "$observation")
observed_support=0
observed_meta_activity=""
if [ "$pattern_count" -eq 1 ]; then
  observed_support=$(jq -r --arg id "$pattern_id" '.patterns[]|select(.id==$id)|.support_count' "$observation")
  observed_meta_activity=$(jq -r --arg id "$pattern_id" '.patterns[]|select(.id==$id)|.meta_activity // ""' "$observation")
fi

authorized_target=UNKNOWN_TRACE
candidate_target=$(jq -r '.operation.target_cell_id // ""' "$candidate")
operation_valid=false
if jq -e '
  .target_denominator_id=="gooo://denominator/self-hosted-evidence-generator/v1" and
  .operation=={
    kind:"CLOSE_ONE_UNKNOWN_CELL",
    target_cell_id:"UNKNOWN_TRACE",
    from_state:"UNKNOWN",
    to_state:"CLOSED",
    closed_reason:"META_BOUND_EXPLICIT_UNKNOWN_PATTERN_APPLIED"
  }
' "$candidate" >/dev/null; then
  operation_valid=true
fi

target_occurrences=$(jq --arg id "$authorized_target" '[.cells[]|select(.id==$id)]|length' "$baseline")
target_state="MISSING"
if [ "$target_occurrences" -eq 1 ]; then
  target_state=$(jq -r --arg id "$authorized_target" '.cells[]|select(.id==$id)|.state' "$baseline")
fi
baseline_refuted=$(jq '[.cells[]|select(.state=="REFUTED")]|length' "$baseline")

selection_state=CLOSED
selection_reason=META_BOUND_CANDIDATE_SELECTED
selection_unknown_class=null
selection_next=NONE
if [ "$operation_valid" != true ]; then
  selection_state=REFUTED
  selection_reason=UNAUTHORIZED_TRANSFORMATION_OPERATION
  selection_next=RESTORE_ALLOWED_ISOLATED_CELL_TRANSITION
elif [ "$pattern_count" -eq 0 ]; then
  selection_state=UNKNOWN
  selection_reason=CANDIDATE_PATTERN_OBSERVATION_MISSING
  selection_unknown_class=DIRECT_MISSING
  selection_next=ADD_PINNED_PATTERN_OBSERVATION
elif [ "$pattern_count" -ne 1 ]; then
  selection_state=REFUTED
  selection_reason=AMBIGUOUS_CANDIDATE_PATTERN_OBSERVATION
  selection_next=REMOVE_DUPLICATE_PATTERN_OBSERVATIONS
elif [ "$observed_support" -lt "$minimum_support" ]; then
  selection_state=UNKNOWN
  selection_reason=CANDIDATE_SUPPORT_BELOW_FIXED_THRESHOLD
  selection_unknown_class=UNBOUNDED
  selection_next=OBSERVE_ADDITIONAL_PINNED_PROJECT_EVIDENCE
elif [ "$observed_support" -ne "$expected_support" ] || [ "$support_total" -ne 4 ]; then
  selection_state=UNKNOWN
  selection_reason=CANDIDATE_SUPPORT_OBSERVATION_STALE
  selection_unknown_class=STALE
  selection_next=REPIN_CANDIDATE_SUPPORT_OBSERVATION
elif [ "$observed_meta_activity" != "$required_meta_activity" ]; then
  selection_state=REFUTED
  selection_reason=CANDIDATE_META_ACTIVITY_MISMATCH
  selection_next=RESTORE_CANDIDATE_META_ACTIVITY_BINDING
elif [ "$target_occurrences" -eq 0 ]; then
  selection_state=UNKNOWN
  selection_reason=CANDIDATE_TARGET_CELL_MISSING
  selection_unknown_class=DIRECT_MISSING
  selection_next=RESTORE_PINNED_BASELINE_TARGET_CELL
elif [ "$target_occurrences" -ne 1 ]; then
  selection_state=REFUTED
  selection_reason=AMBIGUOUS_CANDIDATE_TARGET_CELL
  selection_next=RESTORE_UNIQUE_BASELINE_TARGET_CELL
fi

jq -S -n \
  --arg state "$selection_state" \
  --arg reason "$selection_reason" \
  --arg unknown_class "$selection_unknown_class" \
  --arg next_operation "$selection_next" \
  --arg pattern_id "$pattern_id" \
  --arg required_meta_activity "$required_meta_activity" \
  --arg observed_meta_activity "$observed_meta_activity" \
  --argjson minimum_support "$minimum_support" \
  --argjson expected_support "$expected_support" \
  --argjson observed_support "$observed_support" \
  --argjson support_total "$support_total" '
  {
    schema:"gooo/evidence-generator/candidate-selection/v1",
    state:$state,
    pattern_id:$pattern_id,
    support:{minimum:$minimum_support,expected:$expected_support,observed:$observed_support,total:$support_total},
    meta_activity:{required:$required_meta_activity,observed:$observed_meta_activity},
    claim:(if $state=="UNKNOWN" then
      {state:$state,stage:"OBSERVATION",step:"OBSERVE_CANDIDATE_PATTERN_SUPPORT",reason:$reason,
       unknown_class:$unknown_class,next_operation:$next_operation,blocked_by:[]}
    elif $state=="REFUTED" then
      {state:$state,stage:"SELECTION",step:"SELECT_META_BOUND_CANDIDATE",reason:$reason,
       unknown_class:null,next_operation:$next_operation,blocked_by:[]}
    else
      {state:$state,stage:null,step:null,reason:$reason,unknown_class:null,next_operation:"NONE",blocked_by:[]}
    end)
  }
' > "$output_real/candidate-selection.json"

jq -S . "$baseline" > "$output_real/before-project.json"

apply_allowed=false
if [ "$selection_state" = CLOSED ] && [ "$baseline_refuted" -eq 0 ] && [ "$target_occurrences" -eq 1 ] && [ "$target_state" = UNKNOWN ]; then
  apply_allowed=true
fi

transform_once() {
  local destination=$1
  if [ "$apply_allowed" = true ]; then
    jq -S --arg target "$authorized_target" --arg reason "META_BOUND_EXPLICIT_UNKNOWN_PATTERN_APPLIED" '
      (.cells[]|select(.id==$target)) |= (
        .state="CLOSED" |
        .stage=null |
        .step=null |
        .reason=$reason |
        .unknown_class=null |
        .next_operation="NONE" |
        .blocked_by=[]
      )
    ' "$baseline" > "$destination"
  else
    jq -S . "$baseline" > "$destination"
  fi
}

transform_once "$temporary/after-first.json"
transform_once "$temporary/after-replay.json"
if cmp -s "$temporary/after-first.json" "$temporary/after-replay.json"; then
  replay_equal=true
else
  replay_equal=false
fi
cp "$temporary/after-first.json" "$output_real/after-project.json"

evaluate_project() {
  local project=$1
  local destination=$2
  jq -S -n --slurpfile project "$project" --slurpfile denominator "$target_denominator" '
    ($project[0]) as $p |
    ($denominator[0]) as $d |
    ([$p.cells[]|select(.state=="CLOSED")]|length) as $closed |
    ([$p.cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
    ([$p.cells[]|select(.state=="REFUTED")]|length) as $refuted |
    ([$p.cells[]|select(.state=="UNKNOWN" and
      (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
      (.unknown_class|type)=="string" and (.next_operation|type)=="string" and
      (.blocked_by|type)=="array")]|length) as $unknown_with_six_fields |
    {
      schema:"gooo/evidence-generator/project-evaluation/v1",
      project_id:$p.id,
      denominator_id:$p.denominator_id,
      denominator_identity_match:($p.denominator_id==$d.id),
      cell_count_match:(($p.cells|length)==$d.target_cells),
      cell_ids_match:(([$p.cells[].id]|sort)==([$d.cells[].id]|sort)),
      summary:{total:($p.cells|length),closed:$closed,unknown:$unknown,refuted:$refuted,
        unknown_with_six_fields:$unknown_with_six_fields},
      repository_writes:$p.repository_writes,
      local_test_executions:$p.local_test_executions
    }
  ' > "$destination"
}

evaluate_project "$output_real/before-project.json" "$output_real/before-evaluation.json"
evaluate_project "$output_real/after-project.json" "$output_real/after-evaluation.json"

before_total=$(jq -r '.summary.total' "$output_real/before-evaluation.json")
before_closed=$(jq -r '.summary.closed' "$output_real/before-evaluation.json")
before_unknown=$(jq -r '.summary.unknown' "$output_real/before-evaluation.json")
before_refuted=$(jq -r '.summary.refuted' "$output_real/before-evaluation.json")
after_total=$(jq -r '.summary.total' "$output_real/after-evaluation.json")
after_closed=$(jq -r '.summary.closed' "$output_real/after-evaluation.json")
after_unknown=$(jq -r '.summary.unknown' "$output_real/after-evaluation.json")
after_refuted=$(jq -r '.summary.refuted' "$output_real/after-evaluation.json")
delta_total=$((after_total-before_total))
delta_closed=$((after_closed-before_closed))
delta_unknown=$((after_unknown-before_unknown))
delta_refuted=$((after_refuted-before_refuted))

before_unrelated=$(jq -S -c --arg target "$authorized_target" '{schema,denominator_id,subject_id,repository_writes,local_test_executions,cells:[.cells[]|select(.id!=$target)]}' "$output_real/before-project.json" | sha256sum | awk '{print $1}')
after_unrelated=$(jq -S -c --arg target "$authorized_target" '{schema,denominator_id,subject_id,repository_writes,local_test_executions,cells:[.cells[]|select(.id!=$target)]}' "$output_real/after-project.json" | sha256sum | awk '{print $1}')
if [ "$before_unrelated" = "$after_unrelated" ]; then unrelated_changes=0; else unrelated_changes=1; fi

effect_matches=false
if [ "$apply_allowed" = true ] && jq -e \
  --argjson before_total "$before_total" --argjson before_closed "$before_closed" --argjson before_unknown "$before_unknown" --argjson before_refuted "$before_refuted" \
  --argjson after_total "$after_total" --argjson after_closed "$after_closed" --argjson after_unknown "$after_unknown" --argjson after_refuted "$after_refuted" \
  --argjson delta_total "$delta_total" --argjson delta_closed "$delta_closed" --argjson delta_unknown "$delta_unknown" --argjson delta_refuted "$delta_refuted" \
  --argjson unrelated_changes "$unrelated_changes" '
    .expected_effect.before=={total:$before_total,closed:$before_closed,unknown:$before_unknown,refuted:$before_refuted} and
    .expected_effect.after=={total:$after_total,closed:$after_closed,unknown:$after_unknown,refuted:$after_refuted} and
    .expected_effect.delta=={total:$delta_total,closed:$delta_closed,unknown:$delta_unknown,refuted:$delta_refuted} and
    .expected_effect.target_cell_transitions==1 and .expected_effect.unrelated_cell_changes==$unrelated_changes
  ' "$candidate" >/dev/null; then
  effect_matches=true
fi

overrides='[]'
append_override() {
  local item=$1
  overrides=$(jq -c --argjson item "$item" '. + [$item]' <<<"$overrides")
}

if [ "$pattern_count" -eq 0 ]; then
  append_override "$(jq -n '{cell_id:"PATTERN_OBSERVATION",state:"UNKNOWN",stage:"OBSERVATION",step:"OBSERVE_CANDIDATE_PATTERN_SUPPORT",reason:"CANDIDATE_PATTERN_OBSERVATION_MISSING",unknown_class:"DIRECT_MISSING",next_operation:"ADD_PINNED_PATTERN_OBSERVATION",blocked_by:[]}')"
elif [ "$pattern_count" -ne 1 ]; then
  append_override "$(jq -n '{cell_id:"PATTERN_OBSERVATION",state:"REFUTED",stage:"OBSERVATION",step:"OBSERVE_CANDIDATE_PATTERN_SUPPORT",reason:"AMBIGUOUS_CANDIDATE_PATTERN_OBSERVATION",unknown_class:null,next_operation:"REMOVE_DUPLICATE_PATTERN_OBSERVATIONS",blocked_by:[]}')"
elif [ "$observed_support" -lt "$minimum_support" ]; then
  append_override "$(jq -n '{cell_id:"PATTERN_OBSERVATION",state:"UNKNOWN",stage:"OBSERVATION",step:"OBSERVE_CANDIDATE_PATTERN_SUPPORT",reason:"CANDIDATE_SUPPORT_BELOW_FIXED_THRESHOLD",unknown_class:"UNBOUNDED",next_operation:"OBSERVE_ADDITIONAL_PINNED_PROJECT_EVIDENCE",blocked_by:[]}')"
elif [ "$observed_support" -ne "$expected_support" ]; then
  append_override "$(jq -n '{cell_id:"PATTERN_OBSERVATION",state:"UNKNOWN",stage:"OBSERVATION",step:"OBSERVE_CANDIDATE_PATTERN_SUPPORT",reason:"CANDIDATE_SUPPORT_OBSERVATION_STALE",unknown_class:"STALE",next_operation:"REPIN_CANDIDATE_SUPPORT_OBSERVATION",blocked_by:[]}')"
fi

if [ "$operation_valid" != true ]; then
  append_override "$(jq -n '{cell_id:"CANDIDATE_SELECTION",state:"REFUTED",stage:"SELECTION",step:"SELECT_META_BOUND_CANDIDATE",reason:"UNAUTHORIZED_TRANSFORMATION_OPERATION",unknown_class:null,next_operation:"RESTORE_ALLOWED_ISOLATED_CELL_TRANSITION",blocked_by:[]}')"
elif [ "$pattern_count" -eq 1 ] && [ "$observed_meta_activity" != "$required_meta_activity" ]; then
  append_override "$(jq -n '{cell_id:"CANDIDATE_SELECTION",state:"REFUTED",stage:"SELECTION",step:"SELECT_META_BOUND_CANDIDATE",reason:"CANDIDATE_META_ACTIVITY_MISMATCH",unknown_class:null,next_operation:"RESTORE_CANDIDATE_META_ACTIVITY_BINDING",blocked_by:[]}')"
fi

if [ "$baseline_refuted" -gt 0 ]; then
  append_override "$(jq -n '{cell_id:"BASELINE_SNAPSHOT",state:"REFUTED",stage:"BASELINE",step:"PIN_BASELINE_PROJECT_SNAPSHOT",reason:"BASELINE_COUNTEREXAMPLE_PRESENT",unknown_class:null,next_operation:"REJECT_CANDIDATE",blocked_by:[]}')"
elif [ "$target_occurrences" -eq 0 ]; then
  append_override "$(jq -n '{cell_id:"BASELINE_SNAPSHOT",state:"UNKNOWN",stage:"BASELINE",step:"PIN_BASELINE_PROJECT_SNAPSHOT",reason:"CANDIDATE_TARGET_CELL_MISSING",unknown_class:"DIRECT_MISSING",next_operation:"RESTORE_PINNED_BASELINE_TARGET_CELL",blocked_by:[]}')"
elif [ "$target_occurrences" -ne 1 ] || [ "$target_state" != UNKNOWN ]; then
  append_override "$(jq -n '{cell_id:"BASELINE_SNAPSHOT",state:"REFUTED",stage:"BASELINE",step:"PIN_BASELINE_PROJECT_SNAPSHOT",reason:"BASELINE_TARGET_STATE_INVALID",unknown_class:null,next_operation:"RESTORE_UNKNOWN_BASELINE_TARGET",blocked_by:[]}')"
fi

if [ "$apply_allowed" = true ] && [ "$effect_matches" != true ]; then
  append_override "$(jq -n '{cell_id:"EXACT_EFFECT_RECEIPT",state:"REFUTED",stage:"EFFECT",step:"PUBLISH_EXACT_TRANSFORMATION_EFFECT",reason:"EFFECT_CONTRACT_MISMATCH",unknown_class:null,next_operation:"REJECT_CANDIDATE_EFFECT",blocked_by:[]}')"
fi
if [ "$apply_allowed" = true ] && { [ "$delta_total" -ne 0 ] || [ "$unrelated_changes" -ne 0 ]; }; then
  append_override "$(jq -n '{cell_id:"DENOMINATOR_PRESERVATION",state:"REFUTED",stage:"GUARDRAIL",step:"PRESERVE_FIXED_DENOMINATOR",reason:"CANDIDATE_ESCAPED_AUTHORIZED_CHANGE_SET",unknown_class:null,next_operation:"REJECT_CANDIDATE_EFFECT",blocked_by:[]}')"
fi
if [ "$apply_allowed" = true ] && [ "$replay_equal" != true ]; then
  append_override "$(jq -n '{cell_id:"DETERMINISTIC_REPLAY",state:"REFUTED",stage:"REPLAY",step:"VERIFY_TRANSFORMATION_REPLAY",reason:"TRANSFORMATION_REPLAY_MISMATCH",unknown_class:null,next_operation:"REJECT_NONDETERMINISTIC_CANDIDATE",blocked_by:[]}')"
fi

jq -S -n --slurpfile denominator "$process_denominator" --argjson overrides "$overrides" '
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
    schema:"gooo/evidence-generator/transformation-process-evaluation/v1",
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "INCOMPLETE" else "TRANSFORMATION_EFFECT_CLOSED" end),
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
      {state:"CLOSED",stage:null,step:null,reason:"EXACT_TRANSFORMATION_EFFECT_CONFORMED",
       unknown_class:null,next_operation:"NONE",blocked_by:[]}
    end)
  }
' > "$temporary/process-evaluation.json"

jq -S '
  {
    schema:"gooo/evidence-generator/transformation-activity-bindings/v1",
    source_digest,
    graph_hash,
    core_release:.activity_resolution_observation.core_release,
    summary:.activity_resolution_observation.summary,
    bindings:[.activity_resolution_observation.entries[]|{
      id:(.id // .cell_id),
      activity:(.activity // .selector.name),
      receipt:.receipt
    }]
  }
' "$activity_resolution" > "$output_real/activity-bindings.json"

decision=$(jq -r '.decision' "$temporary/process-evaluation.json")
claim_state=$(jq -r '.claim.state' "$temporary/process-evaluation.json")
fixture_effect_state=$claim_state
if [ "$decision" = TRANSFORMATION_EFFECT_CLOSED ]; then fixture_effect_state=CLOSED; fi

jq -S -n \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --arg decision "$decision" \
  --arg fixture_effect_state "$fixture_effect_state" \
  --arg process_denominator_digest "$process_denominator_digest" \
  --arg target_denominator_digest "$target_denominator_digest" \
  --arg observation_digest "$observation_digest" \
  --arg candidate_digest "$candidate_digest" \
  --arg baseline_digest "$baseline_digest" \
  --arg activity_resolution_digest "$activity_resolution_digest" \
  --arg before_unrelated "$before_unrelated" \
  --arg after_unrelated "$after_unrelated" \
  --argjson replay_equal "$replay_equal" \
  --argjson delta_total "$delta_total" \
  --argjson delta_closed "$delta_closed" \
  --argjson delta_unknown "$delta_unknown" \
  --argjson delta_refuted "$delta_refuted" \
  --argjson unrelated_changes "$unrelated_changes" \
  --slurpfile selection "$output_real/candidate-selection.json" \
  --slurpfile before "$output_real/before-evaluation.json" \
  --slurpfile after "$output_real/after-evaluation.json" \
  --slurpfile process "$temporary/process-evaluation.json" '
  {
    schema:"gooo/evidence-generator/transformation-effect-receipt/v1",
    decision:$decision,
    scenario:$scenario,
    subject_sha:$subject_sha,
    input_digests:{
      process_denominator:$process_denominator_digest,
      target_denominator:$target_denominator_digest,
      observation:$observation_digest,
      candidate:$candidate_digest,
      baseline:$baseline_digest,
      activity_resolution:$activity_resolution_digest
    },
    candidate_selection:$selection[0],
    effect:{
      before:$before[0].summary,
      after:$after[0].summary,
      delta:{total:$delta_total,closed:$delta_closed,unknown:$delta_unknown,refuted:$delta_refuted},
      target_cell_id:"UNKNOWN_TRACE",
      target_cell_transitions:(if $delta_closed==1 and $delta_unknown==-1 then 1 else 0 end),
      unrelated_cell_changes:$unrelated_changes,
      unrelated_before_digest:$before_unrelated,
      unrelated_after_digest:$after_unrelated,
      internal_replay_equal:$replay_equal
    },
    improvement:{
      scope:"PINNED_FIXTURE_CANDIDATE_CONTRACT_AND_TOOLCHAIN_ONLY",
      state:$fixture_effect_state,
      exact_pairs:{required:1,observed:(if $fixture_effect_state=="CLOSED" then 1 else 0 end)},
      generalized_language_improvement:{
        state:"UNKNOWN",required:1,evidence:0,stage:"UTILITY",step:"OBSERVE_INDEPENDENT_ADOPTION",
        reason:"INDEPENDENT_ADOPTION_EVIDENCE_ABSENT",unknown_class:"DIRECT_MISSING",
        next_operation:"OBSERVE_ONE_INDEPENDENT_PUBLIC_CONSUMER",blocked_by:[]
      }
    },
    process:$process[0],
    authority:{
      application_root:"CALLER_OWNED_TEMP_ONLY",
      repository_writes:0,
      denominator_changes:0,
      local_test_executions:0,
      go_build_executions:0,
      go_test_executions:0,
      source_mutation:"FORBIDDEN",
      automatic_promotion:"FORBIDDEN"
    },
    external_utility:{
      state:"UNKNOWN",required:1,evidence:0,stage:"UTILITY",step:"OBSERVE_EXTERNAL_USER_EFFECT",
      reason:"EXTERNAL_USER_EVIDENCE_ABSENT",unknown_class:"DIRECT_MISSING",
      next_operation:"OBSERVE_ONE_EXTERNAL_USER_SESSION",blocked_by:[]
    },
    claim:$process[0].claim
  }
' > "$output_real/effect-receipt.json"

cat > "$output_real/report.md" <<EOF
# Transformation effect receipt

- scenario: \`$scenario\`
- decision: \`$decision\`
- process cells: \`$(jq -r '.summary.closed' "$temporary/process-evaluation.json") CLOSED / $(jq -r '.summary.unknown' "$temporary/process-evaluation.json") UNKNOWN / $(jq -r '.summary.refuted' "$temporary/process-evaluation.json") REFUTED\`
- fixture before: \`$before_closed CLOSED / $before_unknown UNKNOWN / $before_refuted REFUTED\`
- fixture after: \`$after_closed CLOSED / $after_unknown UNKNOWN / $after_refuted REFUTED\`
- exact delta: \`closed $delta_closed, unknown $delta_unknown, refuted $delta_refuted, denominator $delta_total\`
- unrelated cell changes: \`$unrelated_changes\`
- internal deterministic replay: \`$replay_equal\`
- repository writes: \`0\`
- local build and test executions: \`0\`
- generalized language improvement: \`UNKNOWN (0/1)\`
EOF

tracked_files=(
  activity-bindings.json
  after-evaluation.json
  after-project.json
  before-evaluation.json
  before-project.json
  candidate-selection.json
  effect-receipt.json
  report.md
)
entries='[]'
for relative_path in "${tracked_files[@]}"; do
  digest=$(sha256sum "$output_real/$relative_path" | awk '{print $1}')
  size=$(wc -c < "$output_real/$relative_path" | tr -d ' ')
  entries=$(jq -c --arg path "$relative_path" --arg sha256 "$digest" --argjson size "$size" '. + [{path:$path,sha256:$sha256,size_bytes:$size}]' <<<"$entries")
done

jq -S -n --arg subject_sha "$subject_sha" --arg scenario "$scenario" --argjson files "$entries" '
  {schema:"gooo/evidence-generator/transformation-manifest/v1",subject_sha:$subject_sha,
   scenario:$scenario,tracked_file_count:($files|length),files:$files}
' > "$output_real/manifest.json"

test "$(find "$output_real" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 9
