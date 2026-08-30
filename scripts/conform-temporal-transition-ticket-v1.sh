#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: conform-temporal-transition-ticket-v1.sh OUTPUT DENOMINATOR TICKET EVIDENCE ACTIVITY_RESOLUTION SCENARIO REPORT" >&2
  exit 64
fi

output=$1
denominator=$2
ticket_contract=$3
evidence=$4
activity_resolution=$5
scenario=$6
report=$7

test -d "$output"
for file in activity-bindings.json causal-frontier.json evaluation.json human-dossier.md transition-ir.json transition-receipt.json manifest.json; do
  test -f "$output/$file"
done

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}

denominator_digest=$(json_digest "$denominator")
ticket_contract_digest=$(json_digest "$ticket_contract")
evidence_digest=$(json_digest "$evidence")
activity_resolution_digest=$(json_digest "$activity_resolution")

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/manifest/v1" and
  .tracked_file_count==6 and (.files|length)==6 and
  ([.files[].path]|sort)==["activity-bindings.json","causal-frontier.json","evaluation.json","human-dossier.md","transition-ir.json","transition-receipt.json"] and
  all(.files[]; .sha256|test("^[0-9a-f]{64}$"))
' "$output/manifest.json" >/dev/null
while IFS=$'\t' read -r path expected; do
  actual=$(sha256sum "$output/$path" | awk '{print $1}')
  test "$actual" = "$expected"
done < <(jq -r '.files[]|[.path,.sha256]|@tsv' "$output/manifest.json")

jq -e \
  --arg scenario "$scenario" --arg denominator "$denominator_digest" \
  --arg ticket "$ticket_contract_digest" --arg evidence "$evidence_digest" \
  --arg resolution "$activity_resolution_digest" '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/evaluation/v1" and
  .scenario==$scenario and .input_digests.denominator==$denominator and
  .input_digests.ticket_contract==$ticket and .input_digests.evidence==$evidence and
  .input_digests.activity_resolution==$resolution and .summary.total==12 and
  .summary.closed+.summary.unknown+.summary.refuted==12 and
  all(.cells[];
    (.state=="CLOSED" or .state=="UNKNOWN" or .state=="REFUTED") and
    (.blocked_by|type)=="array" and (.frontier|type)=="array" and
    (if .state=="UNKNOWN" then
      (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
      (.unknown_class|type)=="string" and (.next_operation|type)=="string" and
      (.frontier|length)>0
     elif .state=="REFUTED" then
      .unknown_class==null and (.stage|type)=="string" and (.step|type)=="string" and
      (.reason|type)=="string" and (.next_operation|type)=="string" and (.frontier|length)>0
     else
      .unknown_class==null and .next_operation=="NONE"
     end)
  ) and
  (if .summary.refuted>0 then .claim.state=="REFUTED" and .decision=="FAIL_CLOSED"
   elif .summary.unknown>0 then .claim.state=="UNKNOWN" and .decision=="TRANSITION_TICKET_UNKNOWN"
   else .claim.state=="CLOSED" and .decision=="TRANSITION_TICKET_CLOSED" end) and
  (.claim.blocked_by|type)=="array" and
  (if .claim.state=="CLOSED" then (.claim.frontier|length)==0 else (.claim.frontier|length)>0 end)
' "$output/evaluation.json" >/dev/null

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/receipt/v1" and
  .process.total==12 and .process.closed+.process.unknown+.process.refuted==12 and
  .phase_transition.from=="PREDECLARE" and .phase_transition.to=="CONSUME_ONCE" and
  .proof_distribution=={FOUNDATION:4,COHERENCE:4,REGRESSION:4} and
  .indicator_distribution=={DRIVER:4,OUTCOME:4,GUARDRAIL:4} and
  .external_utility.state=="UNKNOWN" and .performance_improvement.state=="UNKNOWN" and
  .authority.repository_writes==0 and .authority.source_mutations==0
' "$output/transition-receipt.json" >/dev/null

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/ir/v1" and
  .transition.phase_order==["PREDECLARE","CONSUME_ONCE"] and
  .transition.future_commit_sha_predeclared==false and
  .transition.typed_mapping=="SQUASH_COMMIT_TO_EXPECTED_TREE" and
  .predeclare.successor_commit_sha_intentionally_late==true
' "$output/transition-ir.json" >/dev/null

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/activity-bindings/v1" and
  .summary=={expected:12,observed:12,closed:12,unknown:0,refuted:0,unique_selectors:12}
' "$output/activity-bindings.json" >/dev/null

jq -e '
  .schema=="gooo/evidence-generator/temporal-transition-ticket/causal-frontier/v1" and
  .precedence=="REFUTED_OVER_UNKNOWN_OVER_CLOSED" and .minimal==true and
  .post_hoc_ticket_forbidden==true and .retroactive_failure_closure_forbidden==true
' "$output/causal-frontier.json" >/dev/null

case "$scenario" in
  normal)
    jq -e '.decision=="TRANSITION_TICKET_CLOSED" and .summary=={total:12,closed:12,unknown:0,refuted:0,direct_missing:0,stale:0,dependency_blocked:0} and .claim.state=="CLOSED"' "$output/evaluation.json" >/dev/null
    jq -e '.ticket.prepared==true and .ticket.consumed_once==true and .ticket.reuse==false' "$output/transition-receipt.json" >/dev/null
    ;;
  prepared-not-consumed)
    jq -e '.decision=="TRANSITION_TICKET_UNKNOWN" and .summary=={total:12,closed:9,unknown:3,refuted:0,direct_missing:1,stale:0,dependency_blocked:2} and .claim.unknown_class=="DIRECT_MISSING" and .claim.reason=="SUCCESSOR_CONSUME_RECEIPT_MISSING"' "$output/evaluation.json" >/dev/null
    ;;
  missing-predecessor-artifact)
    jq -e '.decision=="TRANSITION_TICKET_UNKNOWN" and .summary=={total:12,closed:6,unknown:6,refuted:0,direct_missing:1,stale:0,dependency_blocked:5} and .claim.unknown_class=="DIRECT_MISSING" and .claim.reason=="PREDECESSOR_ARTIFACT_REPORT_MISSING"' "$output/evaluation.json" >/dev/null
    ;;
  expired-stale)
    jq -e '.decision=="TRANSITION_TICKET_UNKNOWN" and .summary=={total:12,closed:7,unknown:5,refuted:0,direct_missing:0,stale:1,dependency_blocked:4} and .claim.unknown_class=="STALE" and .claim.reason=="TRANSITION_TICKET_EXPIRED_OR_STALE"' "$output/evaluation.json" >/dev/null
    ;;
  dependency-blocked)
    jq -e '.decision=="TRANSITION_TICKET_UNKNOWN" and .summary=={total:12,closed:2,unknown:10,refuted:0,direct_missing:0,stale:0,dependency_blocked:10} and .claim.unknown_class=="DEPENDENCY_BLOCKED" and .claim.blocked_by==["PREDECESSOR_IDENTITY_SOURCE"]' "$output/evaluation.json" >/dev/null
    ;;
  target-mismatch)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="TARGET_BRANCH_MISMATCH"' "$output/evaluation.json" >/dev/null
    ;;
  tree-mismatch)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="SUCCESSOR_TREE_DIGEST_MISMATCH"' "$output/evaluation.json" >/dev/null
    ;;
  policy-mismatch)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="POLICY_DIGEST_MISMATCH"' "$output/evaluation.json" >/dev/null
    ;;
  toolchain-mismatch)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="TOOLCHAIN_DIGEST_MISMATCH"' "$output/evaluation.json" >/dev/null
    ;;
  workflow-mismatch)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="WORKFLOW_DIGEST_MISMATCH"' "$output/evaluation.json" >/dev/null
    ;;
  consume-before-prepare)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="CONSUME_BEFORE_PREPARE"' "$output/evaluation.json" >/dev/null
    ;;
  replay-reuse)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="CONSUMED_TICKET_REUSE"' "$output/evaluation.json" >/dev/null
    ;;
  digest-laundering)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:6,unknown:0,refuted:6,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="DIGEST_LAUNDERING_DETECTED"' "$output/evaluation.json" >/dev/null
    ;;
  unknown-top-level-decision)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:10,unknown:0,refuted:2,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="UNRECOGNIZED_TOP_LEVEL_DECISION"' "$output/evaluation.json" >/dev/null
    ;;
  post-hoc-ticket)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="POST_HOC_TICKET_FORBIDDEN"' "$output/evaluation.json" >/dev/null
    ;;
  retroactive-closure)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="RETROACTIVE_FAILURE_CLOSURE_FORBIDDEN"' "$output/evaluation.json" >/dev/null
    ;;
  authority-write-escalation)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:9,unknown:0,refuted:3,direct_missing:0,stale:0,dependency_blocked:0} and .claim.reason=="AUTHORITY_WRITE_ESCALATION"' "$output/evaluation.json" >/dev/null
    ;;
  mixed)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:2,refuted:3,direct_missing:0,stale:1,dependency_blocked:1} and .claim.state=="REFUTED" and .claim.reason=="TARGET_BRANCH_MISMATCH" and .claim.precedence=="REFUTED_OVER_UNKNOWN" and ([.cells[]|select(.state=="UNKNOWN" and .unknown_class=="STALE")]|length)==1' "$output/evaluation.json" >/dev/null
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 67
    ;;
esac

jq -S -n \
  --arg scenario "$scenario" --arg subject_sha "$(jq -r '.subject_sha' "$output/evaluation.json")" \
  --slurpfile evaluation "$output/evaluation.json" --slurpfile receipt "$output/transition-receipt.json" \
  '{schema:"gooo/evidence-generator/temporal-transition-ticket/conformance/v1",decision:"CONFORMANT",
    scenario:$scenario,subject_sha:$subject_sha,summary:$evaluation[0].summary,claim:$evaluation[0].claim,
    ticket:$receipt[0].ticket,precedence:($evaluation[0].claim.precedence // "NONE")}' > "$report"
