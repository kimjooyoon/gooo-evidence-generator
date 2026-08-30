#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "usage: evaluate-temporal-transition-ticket-v1.sh REPOSITORY DENOMINATOR TICKET EVIDENCE ACTIVITY_RESOLUTION OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
denominator=$2
ticket_contract=$3
evidence=$4
activity_resolution=$5
output=$6
subject_sha=$7
scenario=$8

for input in "$denominator" "$ticket_contract" "$evidence" "$activity_resolution"; do
  test -f "$input"
done

repository_real=$(realpath "$repository")
if [ -d "$output" ] && find "$output" -mindepth 1 -print -quit | grep -q .; then
  echo "output directory must be empty" >&2
  exit 65
fi
mkdir -p "$output"
output_real=$(realpath "$output")
case "$output_real" in
  "$repository_real"|"$repository_real"/*)
    echo "output directory must be outside the source repository" >&2
    exit 65
    ;;
esac

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

denominator_digest=$(json_digest "$denominator")
ticket_contract_digest=$(json_digest "$ticket_contract")
evidence_digest=$(json_digest "$evidence")
activity_resolution_digest=$(json_digest "$activity_resolution")

ticket_contract_valid=false
if jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/v1" and
  .phase_order==["PREDECLARE","CONSUME_ONCE"] and
  (.predeclare_required_fields|length)==15 and
  (.consume_required_fields|length)==10 and
  .future_commit_mapping.mapping_type=="SQUASH_COMMIT_TO_EXPECTED_TREE" and
  .future_commit_mapping.predeclare_field=="expected_tree_digest" and
  .future_commit_mapping.consume_field=="merge_receipt.tree_digest" and
  .future_commit_mapping.commit_sha_predeclared==false and
  .future_commit_mapping.typed==true and
  ([.forbidden[]]|sort)==["AUTHORITY_WRITE_ESCALATION","DIGEST_LAUNDERING","POST_HOC_TICKET","RETROACTIVE_FAILURE_CLOSURE","TICKET_REUSE"]
' "$ticket_contract" >/dev/null 2>&1; then
  ticket_contract_valid=true
fi

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket-denominator/v1" and
  .target_cells==12 and (.cells|length)==12 and
  ([.cells[].id]|unique|length)==12 and ([.cells[].activity]|unique|length)==12 and
  ([.cells[].ordinal]|sort)==[range(1;13)] and
  ([.cells[]|select(.proof_choice=="FOUNDATION")]|length)==4 and
  ([.cells[]|select(.proof_choice=="COHERENCE")]|length)==4 and
  ([.cells[]|select(.proof_choice=="REGRESSION")]|length)==4 and
  ([.cells[]|select(.indicator_class=="DRIVER")]|length)==4 and
  ([.cells[]|select(.indicator_class=="OUTCOME")]|length)==4 and
  ([.cells[]|select(.indicator_class=="GUARDRAIL")]|length)==4
' "$denominator" >/dev/null
jq -e '.activity_resolution_observation.summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12}' "$activity_resolution" >/dev/null

value() {
  jq -r "$1 | if . == null then \"__MISSING__\" else tostring end" "$evidence" 2>/dev/null || echo __MISSING__
}

evidence_valid=false
if jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/evidence/v1" and
  (.predecessor|type)=="object" and (.proposal|type)=="object" and
  (.ticket|type)=="object" and (.ticket.predeclare|type)=="object" and
  (.consume|type)=="object" and (.consume.successor|type)=="object" and
  (.consume.successor.merge_receipt|type)=="object" and (.authority|type)=="object" and
  (.external_utility|type)=="object" and (.performance|type)=="object" and
  (.ticket.predeclare.expected_pr_number|type)=="number" and
  (.consume.successor.pr_number|type)=="number" and
  all([.predecessor.artifact_digest,.predecessor.observed_artifact_digest,
       .predecessor.report_digest,.predecessor.observed_report_digest,
       .proposal.proposal_digest,.proposal.observed_digest,
       .proposal.expected_tree_digest,.ticket.predeclare.expected_tree_digest,
       .ticket.predeclare.predecessor_artifact_digest,
       .ticket.predeclare.predecessor_report_digest,
       .ticket.predeclare.proposal_digest][];
      type=="string" and test("^sha256:[0-9a-f]{64}$"))
' "$evidence" >/dev/null 2>&1; then
  evidence_valid=true
fi

upper_decision=$(value '.upper_decision')
identity_state=$(value '.predecessor.identity_state')
predecessor_identity=$(value '.predecessor.identity')
artifact_present=$(value '.predecessor.artifact_present')
artifact_digest=$(value '.predecessor.artifact_digest')
observed_artifact_digest=$(value '.predecessor.observed_artifact_digest')
report_digest=$(value '.predecessor.report_digest')
observed_report_digest=$(value '.predecessor.observed_report_digest')
proposal_digest=$(value '.proposal.proposal_digest')
observed_proposal_digest=$(value '.proposal.observed_digest')
proposal_expected_tree=$(value '.proposal.expected_tree_digest')
proposal_target_branch=$(value '.proposal.target_branch')
proposal_policy_digest=$(value '.proposal.policy_digest')
proposal_toolchain_digest=$(value '.proposal.toolchain_digest')
proposal_workflow_digest=$(value '.proposal.workflow_digest')
proposal_proof_choice=$(value '.proposal.expected_proof_choice')
predeclare_identity=$(value '.ticket.predeclare.predecessor_identity')
ticket_phase=$(value '.ticket.phase')
ticket_prepared=$(value '.ticket.prepared')
predeclared_before_successor=$(value '.ticket.predeclared_before_successor')
post_hoc=$(value '.ticket.post_hoc')
retroactive_closure=$(value '.ticket.retroactive_closure_requested')
ticket_fresh=$(value '.ticket.fresh')
predeclare_ticket_id=$(value '.ticket.predeclare.ticket_id')
predeclare_expected_tree=$(value '.ticket.predeclare.expected_tree_digest')
predeclare_pr=$(value '.ticket.predeclare.expected_pr_number')
predeclare_target_branch=$(value '.ticket.predeclare.target_branch')
predeclare_policy_digest=$(value '.ticket.predeclare.policy_digest')
predeclare_toolchain_digest=$(value '.ticket.predeclare.toolchain_digest')
predeclare_workflow_digest=$(value '.ticket.predeclare.workflow_digest')
predeclare_proof_choice=$(value '.ticket.predeclare.expected_proof_choice')
predeclare_proposal_digest=$(value '.ticket.predeclare.proposal_digest')
predeclare_artifact_digest=$(value '.ticket.predeclare.predecessor_artifact_digest')
predeclare_report_digest=$(value '.ticket.predeclare.predecessor_report_digest')
consume_attempted=$(value '.consume.attempted')
consume_reuse=$(value '.consume.reuse')
consume_ticket_id=$(value '.consume.ticket_id')
successor_commit=$(value '.consume.successor.commit_sha')
successor_tree=$(value '.consume.successor.tree_digest')
successor_pr=$(value '.consume.successor.pr_number')
successor_target_branch=$(value '.consume.successor.target_branch')
successor_policy_digest=$(value '.consume.successor.policy_digest')
successor_toolchain_digest=$(value '.consume.successor.toolchain_digest')
successor_workflow_digest=$(value '.consume.successor.workflow_digest')
successor_proof_choice=$(value '.consume.successor.proof_choice')
merge_mapping_type=$(value '.consume.successor.merge_receipt.mapping_type')
merge_typed=$(value '.consume.successor.merge_receipt.typed')
merge_commit=$(value '.consume.successor.merge_receipt.commit_sha')
merge_tree=$(value '.consume.successor.merge_receipt.tree_digest')
write_escalation=$(value '.authority.write_escalation')
repository_writes=$(value '.authority.repository_writes')
source_mutations=$(value '.authority.source_mutations')

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
    --arg reason "$reason" --arg unknown_class "$unknown_class" --arg next_operation "$next_operation" \
    --argjson blocked_by "$blocked_by" --argjson priority "$priority" \
    '{cell_id:$cell_id,state:$state,stage:$stage,step:$step,reason:$reason,
      unknown_class:(if $unknown_class=="" then null else $unknown_class end),
      next_operation:$next_operation,blocked_by:$blocked_by,
      frontier:[{stage:$stage,step:$step}],priority:$priority}'
}

if [ "$ticket_contract_valid" != true ] || [ "$evidence_valid" != true ]; then
  append_override "$(decision_json PREDECLARE REFUTED INPUT VALIDATE_TRANSITION_INPUTS MALFORMED_TRANSITION_INPUT '' RESTORE_TRANSITION_INPUTS '[]' 130)"
fi

if [ "$upper_decision" != CLOSED ]; then
  append_override "$(decision_json DECISION_PRECEDENCE REFUTED CONTROL VALIDATE_TOP_LEVEL_DECISION UNRECOGNIZED_TOP_LEVEL_DECISION '' RESTORE_EXPLICIT_TOP_LEVEL_DECISION '[]' 129)"
fi

if [ "$write_escalation" = true ] || [ "$repository_writes" != 0 ] || [ "$source_mutations" != 0 ]; then
  append_override "$(decision_json CONSUME_ONCE REFUTED AUTHORITY ENFORCE_CALLER_OWNED_BOUNDARY AUTHORITY_WRITE_ESCALATION '' REJECT_AUTHORITY_ESCALATION '[]' 128)"
fi

if [ "$post_hoc" = true ]; then
  append_override "$(decision_json PREDECLARE REFUTED PREDECLARE ENFORCE_PREDECESSOR_ORDER POST_HOC_TICKET_FORBIDDEN '' ISSUE_PREDECLARE_BEFORE_SUCCESSOR '[]' 127)"
fi

if [ "$retroactive_closure" = true ]; then
  append_override "$(decision_json PREDECLARE REFUTED PREDECLARE REJECT_RETROACTIVE_FAILURE_CLOSURE RETROACTIVE_FAILURE_CLOSURE_FORBIDDEN '' REQUIRE_CURRENT_TRANSITION_TICKET '[]' 126)"
fi

if [ "$predecessor_identity" != "$predeclare_identity" ]; then
  append_override "$(decision_json PREDECESSOR_IDENTITY REFUTED PREDECLARE VALIDATE_PREDECESSOR_IDENTITY PREDECESSOR_IDENTITY_MISMATCH '' RESTORE_PREDECESSOR_IDENTITY_BINDING '[]' 124)"
fi

if [ "$proposal_expected_tree" != "$predeclare_expected_tree" ] ||
   [ "$proposal_target_branch" != "$predeclare_target_branch" ] ||
   [ "$proposal_policy_digest" != "$predeclare_policy_digest" ] ||
   [ "$proposal_toolchain_digest" != "$predeclare_toolchain_digest" ] ||
   [ "$proposal_workflow_digest" != "$predeclare_workflow_digest" ] ||
   [ "$proposal_proof_choice" != "$predeclare_proof_choice" ]; then
  append_override "$(decision_json PROPOSAL_TREE_EXPECTATION REFUTED PREDECLARE VALIDATE_PREDECLARE_BINDINGS PREDECLARE_FIELD_MISMATCH '' RESTORE_PREDECLARE_BINDINGS '[]' 123)"
fi

if [ "$artifact_present" = true ] && {
  [ "$artifact_digest" != "$observed_artifact_digest" ] ||
  [ "$report_digest" != "$observed_report_digest" ] ||
  [ "$proposal_digest" != "$observed_proposal_digest" ] ||
  [ "$predeclare_artifact_digest" != "$artifact_digest" ] ||
  [ "$predeclare_report_digest" != "$report_digest" ] ||
  [ "$predeclare_proposal_digest" != "$proposal_digest" ];
}; then
  append_override "$(decision_json PREDECESSOR_ARTIFACT_REPORT REFUTED DIGEST VALIDATE_IMMUTABLE_DIGESTS DIGEST_LAUNDERING_DETECTED '' RESTORE_IMMUTABLE_DIGEST_CHAIN '[]' 125)"
fi

if [ "$identity_state" = UNKNOWN ]; then
  append_override "$(decision_json PREDECESSOR_IDENTITY UNKNOWN DEPENDENCY RESOLVE_PREDECESSOR_IDENTITY PREDECESSOR_IDENTITY_UNAVAILABLE DEPENDENCY_BLOCKED RESOLVE_PREDECESSOR_IDENTITY '[\"PREDECESSOR_IDENTITY_SOURCE\"]' 60)"
fi

if [ "$artifact_present" != true ] && [ "$artifact_present" != __MISSING__ ]; then
  append_override "$(decision_json PREDECESSOR_ARTIFACT_REPORT UNKNOWN PREDECLARE BIND_PREDECESSOR_ARTIFACT_REPORT PREDECESSOR_ARTIFACT_REPORT_MISSING DIRECT_MISSING RESTORE_IMMUTABLE_PREDECESSOR_ARTIFACT_REPORT '[]' 59)"
fi

if [ "$ticket_fresh" != true ] && [ "$ticket_fresh" != __MISSING__ ]; then
  append_override "$(decision_json PREDECLARE UNKNOWN PREDECLARE CHECK_TICKET_EXPIRY TRANSITION_TICKET_EXPIRED_OR_STALE STALE ISSUE_NEW_PREDECLARE_TICKET '[]' 58)"
fi

if [ "$ticket_phase" = CLOSED ] || [ "$consume_reuse" = true ]; then
  append_override "$(decision_json CONSUME_ONCE REFUTED CONSUME ENFORCE_SINGLE_USE CONSUMED_TICKET_REUSE '' ISSUE_NEW_TICKET_FOR_NEW_SUCCESSOR '[]' 124)"
elif [ "$ticket_phase" != PREPARED ] || [ "$ticket_prepared" != true ] || [ "$predeclared_before_successor" != true ]; then
  append_override "$(decision_json PREDECLARE REFUTED PREDECLARE ENFORCE_PREPARE_BEFORE_CONSUME CONSUME_BEFORE_PREPARE '' PREDECLARE_BEFORE_CONSUME '[]' 123)"
elif [ "$consume_attempted" != true ]; then
  append_override "$(decision_json CONSUME_ONCE UNKNOWN CONSUME CONSUME_TRANSITION_TICKET_ONCE SUCCESSOR_CONSUME_RECEIPT_MISSING DIRECT_MISSING PROVIDE_SUCCESSOR_CONSUME_RECEIPT '[]' 57)"
else
  mismatch_reason=''
  mismatch_operation=''
  if [ "$consume_ticket_id" != "$predeclare_ticket_id" ]; then
    mismatch_reason=TICKET_ID_MISMATCH
    mismatch_operation=RESTORE_TICKET_ID_BINDING
  elif [ "$successor_pr" != "$predeclare_pr" ]; then
    mismatch_reason=SUCCESSOR_PR_NUMBER_MISMATCH
    mismatch_operation=RESTORE_SUCCESSOR_PR_BINDING
  elif [ "$successor_target_branch" != "$predeclare_target_branch" ]; then
    mismatch_reason=TARGET_BRANCH_MISMATCH
    mismatch_operation=RESTORE_TARGET_BRANCH_BINDING
  elif [ "$successor_tree" != "$predeclare_expected_tree" ] ||
       [ "$merge_tree" != "$predeclare_expected_tree" ] ||
       [ "$merge_tree" != "$successor_tree" ] ||
       [ "$merge_mapping_type" != SQUASH_COMMIT_TO_EXPECTED_TREE ] ||
       [ "$merge_typed" != true ]; then
    mismatch_reason=SUCCESSOR_TREE_DIGEST_MISMATCH
    mismatch_operation=RESTORE_TYPED_EXPECTED_TREE_MAPPING
  elif [ "$successor_policy_digest" != "$predeclare_policy_digest" ]; then
    mismatch_reason=POLICY_DIGEST_MISMATCH
    mismatch_operation=RESTORE_POLICY_DIGEST_BINDING
  elif [ "$successor_toolchain_digest" != "$predeclare_toolchain_digest" ]; then
    mismatch_reason=TOOLCHAIN_DIGEST_MISMATCH
    mismatch_operation=RESTORE_TOOLCHAIN_DIGEST_BINDING
  elif [ "$successor_workflow_digest" != "$predeclare_workflow_digest" ]; then
    mismatch_reason=WORKFLOW_DIGEST_MISMATCH
    mismatch_operation=RESTORE_WORKFLOW_DIGEST_BINDING
  elif [ "$successor_proof_choice" != "$predeclare_proof_choice" ]; then
    mismatch_reason=PROOF_CHOICE_MISMATCH
    mismatch_operation=RESTORE_EXPECTED_PROOF_BINDING
  elif [ "$merge_commit" != "$successor_commit" ]; then
    mismatch_reason=MERGE_RECEIPT_COMMIT_MAPPING_MISMATCH
    mismatch_operation=RESTORE_MERGE_RECEIPT_COMMIT_MAPPING
  fi
  if [ -n "$mismatch_reason" ]; then
    append_override "$(decision_json CONSUME_ONCE REFUTED CONSUME VALIDATE_SUCCESSOR_BINDINGS "$mismatch_reason" '' "$mismatch_operation" '[]' 110)"
  fi
fi

temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT

jq -S -n \
  --slurpfile denominator "$denominator" \
  --argjson overrides "$overrides" \
  --argjson ticket_contract_valid "$ticket_contract_valid" \
  --argjson evidence_valid "$evidence_valid" \
  --arg upper_decision "$upper_decision" \
  --arg scenario "$scenario" '
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
  ([$evaluation.cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$evaluation.decisions[]|select(.state=="REFUTED")]|if length==0 then null else max_by(.priority) end) as $first_refuted |
  ([$evaluation.decisions[]|select(.state=="UNKNOWN")]|if length==0 then null else max_by(.priority) end) as $first_unknown |
  {
    schema:"gooo/evidence-generator/temporal-transition-ticket/evaluation/v1",
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "TRANSITION_TICKET_UNKNOWN" else "TRANSITION_TICKET_CLOSED" end),
    summary:{total:$denominator[0].target_cells,closed:$closed,unknown:$unknown,refuted:$refuted,
      direct_missing:$direct_missing,stale:$stale,dependency_blocked:$dependency_blocked},
    cells:$evaluation.cells,
    control_input:{ticket_contract_valid:$ticket_contract_valid,evidence_valid:$evidence_valid,
      upper_decision:$upper_decision,scenario:$scenario},
    claim:(if $first_refuted!=null then
      {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,
       unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by,
       frontier:$first_refuted.frontier,precedence:"REFUTED_OVER_UNKNOWN"}
    elif $first_unknown!=null then
      {state:"UNKNOWN",stage:$first_unknown.stage,step:$first_unknown.step,reason:$first_unknown.reason,
       unknown_class:$first_unknown.unknown_class,next_operation:$first_unknown.next_operation,
       blocked_by:$first_unknown.blocked_by,frontier:$first_unknown.frontier,precedence:"UNKNOWN_OVER_CLOSED"}
    else
      {state:"CLOSED",stage:null,step:null,reason:"TRANSITION_TICKET_CONSUMED_ONCE",
       unknown_class:null,next_operation:"NONE",blocked_by:[],frontier:[],precedence:"CLOSED"}
    end),
    transition:{from:"PREDECLARE",to:"CONSUME_ONCE",ticket_state:(if $refuted>0 then "REFUTED" elif $unknown>0 then "UNKNOWN" else "CLOSED" end)},
    authority:{application_root:"CALLER_OWNED_TEMP_ONLY",repository_writes:0,source_mutations:0,
      denominator_changes:0,automatic_retroactive_closure:false,local_test_executions:0},
    external_utility:{state:"UNKNOWN",reason:"INDEPENDENT_EXTERNAL_UTILITY_EVIDENCE_ABSENT",evidence:0,required:1},
    performance_improvement:{state:"UNKNOWN",reason:"COMPARABLE_BEFORE_AFTER_PERFORMANCE_EVIDENCE_ABSENT",evidence:0,required:1}
  }
' > "$temporary/evaluation.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg denominator_digest "$denominator_digest" --arg ticket_contract_digest "$ticket_contract_digest" \
  --arg evidence_digest "$evidence_digest" --arg activity_resolution_digest "$activity_resolution_digest" \
  --slurpfile evidence "$evidence" --slurpfile evaluation "$temporary/evaluation.json" '
  ($evidence[0]) as $e |
  {
    schema:"gooo/evidence-generator/temporal-transition-ticket/ir/v1",
    subject_sha:$subject_sha,scenario:$scenario,
    transition:{phase_order:["PREDECLARE","CONSUME_ONCE"],future_commit_sha_predeclared:false,
      typed_mapping:"SQUASH_COMMIT_TO_EXPECTED_TREE",expected_tree_digest:$e.ticket.predeclare.expected_tree_digest},
    predeclare:($e.ticket.predeclare + {
      predecessor_artifact_observed_digest:$e.predecessor.observed_artifact_digest,
      predecessor_report_observed_digest:$e.predecessor.observed_report_digest,
      proposal_observed_digest:$e.proposal.observed_digest,
      successor_commit_sha_intentionally_late:true
    }),
    consume:($e.consume + {actual_successor_commit_sha:$e.consume.successor.commit_sha,
      actual_successor_tree_digest:$e.consume.successor.tree_digest}),
    authority:$e.authority,
    evaluation_state:$evaluation[0].transition.ticket_state,
    input_digests:{denominator:$denominator_digest,ticket_contract:$ticket_contract_digest,
      evidence:$evidence_digest,activity_resolution:$activity_resolution_digest}
  }
' > "$output_real/transition-ir.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg denominator_digest "$denominator_digest" --arg ticket_contract_digest "$ticket_contract_digest" \
  --arg evidence_digest "$evidence_digest" --arg activity_resolution_digest "$activity_resolution_digest" \
  --slurpfile evidence "$evidence" --slurpfile evaluation "$temporary/evaluation.json" '
  ($evidence[0]) as $e |
  {
    schema:"gooo/evidence-generator/temporal-transition-ticket/receipt/v1",
    subject_sha:$subject_sha,scenario:$scenario,
    decision:$evaluation[0].decision,state:$evaluation[0].claim.state,
    phase_transition:{from:"PREDECLARE",to:"CONSUME_ONCE",
      predeclare:([$evaluation[0].cells[]|select(.id=="PREDECLARE")][0]),
      consume_once:([$evaluation[0].cells[]|select(.id=="CONSUME_ONCE")][0])},
    ticket:{ticket_id:$e.ticket.predeclare.ticket_id,nonce:$e.ticket.predeclare.nonce,
      prepared:($e.ticket.prepared==true),consumed_once:($evaluation[0].claim.state=="CLOSED"),
      reuse:($e.consume.reuse==true),predeclared_before_successor:($e.ticket.predeclared_before_successor==true)},
    process:$evaluation[0].summary,cells:$evaluation[0].cells,claim:$evaluation[0].claim,
    future_commit_mapping:{type:"SQUASH_COMMIT_TO_EXPECTED_TREE",typed:true,
      expected_tree_digest:$e.ticket.predeclare.expected_tree_digest,
      merge_receipt_tree_digest:($e.consume.successor.merge_receipt.tree_digest // null),
      successor_commit_sha:($e.consume.successor.commit_sha // null)},
    external_utility:$evaluation[0].external_utility,
    performance_improvement:$evaluation[0].performance_improvement,
    authority:$evaluation[0].authority,
    proof_distribution:{FOUNDATION:4,COHERENCE:4,REGRESSION:4},
    indicator_distribution:{DRIVER:4,OUTCOME:4,GUARDRAIL:4},
    input_digests:{denominator:$denominator_digest,ticket_contract:$ticket_contract_digest,
      evidence:$evidence_digest,activity_resolution:$activity_resolution_digest}
  }
' > "$output_real/transition-receipt.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg evidence_digest "$evidence_digest" --slurpfile evidence "$evidence" \
  --slurpfile evaluation "$temporary/evaluation.json" '
  {
    schema:"gooo/evidence-generator/temporal-transition-ticket/causal-frontier/v1",
    subject_sha:$subject_sha,scenario:$scenario,state:$evaluation[0].claim.state,
    precedence:"REFUTED_OVER_UNKNOWN_OVER_CLOSED",minimal:true,
    claim:$evaluation[0].claim,
    frontier:([$evaluation[0].cells[]|select(.state!="CLOSED")|{
      cell_id,id,stage,step,state,reason,unknown_class,next_operation,blocked_by,frontier
    }]),
    retained_unknown_cells:([$evaluation[0].cells[]|select(.state=="UNKNOWN")|.id]|sort),
    evidence_digest:$evidence_digest,
    post_hoc_ticket_forbidden:true,retroactive_failure_closure_forbidden:true
  }
' > "$output_real/causal-frontier.json"

jq -S -n \
  --arg subject_sha "$subject_sha" --arg source_digest "$activity_resolution_digest" \
  --slurpfile resolution "$activity_resolution" \
  '{schema:"gooo/evidence-generator/temporal-transition-ticket/activity-bindings/v1",
    subject_sha:$subject_sha,source_digest:$source_digest,
    core_release:$resolution[0].activity_resolution_observation.core_release,
    summary:$resolution[0].activity_resolution_observation.summary,
    bindings:[$resolution[0].activity_resolution_observation.entries[]|{ordinal,id,activity,receipt:.receipt}]}' \
  > "$output_real/activity-bindings.json"

jq -S --arg subject_sha "$subject_sha" --arg scenario "$scenario" \
  --arg denominator_digest "$denominator_digest" --arg ticket_contract_digest "$ticket_contract_digest" \
  --arg evidence_digest "$evidence_digest" --arg activity_resolution_digest "$activity_resolution_digest" \
  --slurpfile evaluation "$temporary/evaluation.json" \
  '$evaluation[0] + {subject_sha:$subject_sha,scenario:$scenario,
    input_digests:{denominator:$denominator_digest,ticket_contract:$ticket_contract_digest,
      evidence:$evidence_digest,activity_resolution:$activity_resolution_digest}}' \
  > "$output_real/evaluation.json"

decision=$(jq -r '.decision' "$temporary/evaluation.json")
claim_state=$(jq -r '.claim.state' "$temporary/evaluation.json")
claim_stage=$(jq -r '.claim.stage // "NONE"' "$temporary/evaluation.json")
claim_step=$(jq -r '.claim.step // "NONE"' "$temporary/evaluation.json")
claim_reason=$(jq -r '.claim.reason' "$temporary/evaluation.json")
claim_class=$(jq -r '.claim.unknown_class // "NONE"' "$temporary/evaluation.json")
claim_blocked_by=$(jq -c '.claim.blocked_by' "$temporary/evaluation.json")
cat > "$output_real/human-dossier.md" <<EOF
# PREDECLARE to CONSUME_ONCE transition dossier

- scenario: \`$scenario\`
- evaluator decision: \`$decision\`
- transition state: \`$claim_state\`
- causal frontier: \`$claim_stage/$claim_step\` \`$claim_reason\` (\`$claim_class\`)
- blocked by: \`$claim_blocked_by\`
- ticket phases: \`PREDECLARE -> CONSUME_ONCE\`
- future squash mapping: \`expected_tree_digest -> typed merge_receipt.tree_digest\`
- source repository writes: \`0\`
- post-hoc ticket creation: \`FORBIDDEN\`
- retroactive historical failure closure: \`FORBIDDEN\`
- external utility: \`UNKNOWN; independent evidence absent\`
- performance improvement: \`UNKNOWN; comparable before/after evidence absent\`
EOF

tracked=(activity-bindings.json causal-frontier.json evaluation.json human-dossier.md transition-ir.json transition-receipt.json)
manifest_entries='[]'
for file in "${tracked[@]}"; do
  digest=$(sha256sum "$output_real/$file" | awk '{print $1}')
  manifest_entries=$(jq -c --arg path "$file" --arg digest "$digest" '. + [{path:$path,sha256:$digest}]' <<<"$manifest_entries")
done
manifest_error="$temporary/manifest-jq-error"
if ! jq -S -n \
  --arg subject_sha "$subject_sha" --arg scenario "$scenario" --arg source_digest "$activity_resolution_digest" \
  --argjson manifest_files "$manifest_entries" \
  '{schema:"gooo/evidence-generator/temporal-transition-ticket/manifest/v1",subject_sha:$subject_sha,scenario:$scenario,
    tracked_file_count:6,source_activity_resolution_digest:$source_digest,files:$manifest_files}' \
  > "$output_real/manifest.json" 2> "$manifest_error"; then
  cat "$manifest_error" >&2
  exit 4
fi
