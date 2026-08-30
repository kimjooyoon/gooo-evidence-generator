#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 8 ]; then
  echo "usage: conform-test-receipt-reuse-v1.sh OUTPUT DENOMINATOR CURRENT_SCOPE RECEIPT RESULT ACTIVITY_RESOLUTION SCENARIO REPORT" >&2
  exit 64
fi

output=$(realpath "$1")
denominator=$2
current_scope=$3
receipt=$4
result=$5
activity_resolution=$6
scenario=$7
report=$8

expected_files=(input-observation.json manifest.json report.md reuse-report.json)
test "$(find "$output" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
for relative_path in "${expected_files[@]}"; do test -f "$output/$relative_path"; done

manifest="$output/manifest.json"
reuse_report="$output/reuse-report.json"
jq -e '.schema=="gooo/evidence-generator/test-receipt-reuse-manifest/v1" and .tracked_file_count==3 and (.files|length)==3' "$manifest" >/dev/null
verified=0
while IFS=$'\t' read -r relative_path expected_digest expected_size; do
  case "$relative_path" in /*|*..*) exit 65 ;; esac
  test "$(sha256sum "$output/$relative_path" | awk '{print $1}')" = "$expected_digest"
  test "$(wc -c < "$output/$relative_path" | tr -d ' ')" -eq "$expected_size"
  verified=$((verified+1))
done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
test "$verified" -eq 3

json_digest() {
  jq -S -c . "$1" | sha256sum | awk '{print $1}'
}
current_scope_digest=$(json_digest "$current_scope")
resolution_digest=$(json_digest "$activity_resolution")
receipt_digest=MISSING
result_digest=MISSING
if [ -f "$receipt" ]; then receipt_digest=$(json_digest "$receipt"); fi
if [ -f "$result" ]; then result_digest=$(sha256sum "$result" | awk '{print $1}'); fi

jq -e \
  --arg current_scope "$current_scope_digest" \
  --arg receipt "$receipt_digest" \
  --arg result "$result_digest" \
  --arg resolution "$resolution_digest" \
  --arg scenario "$scenario" '
  .schema=="gooo/evidence-generator/test-receipt-reuse-report/v1" and
  .scenario==$scenario and
  .input_digests.current_scope==$current_scope and
  .input_digests.receipt==$receipt and
  .input_digests.result==$result and
  .input_digests.activity_resolution==$resolution and
  .summary.total==12 and .summary.closed+.summary.unknown+.summary.refuted==12 and
  .authority.repository_writes==0 and .authority.source_mutations==0 and
  .authority.local_test_executions==0 and .authority.consumer_test_executions==0 and
  .improvement.saved_test_ms.state=="UNKNOWN" and
  .external_utility.state=="UNKNOWN" and
  all(.cells[]|select(.state=="UNKNOWN");
    (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
    (.unknown_class|type)=="string" and (.next_operation|type)=="string" and (.blocked_by|type)=="array") and
  (if .summary.refuted>0 then .claim.state=="REFUTED"
   elif .summary.unknown>0 then .claim.state=="UNKNOWN"
   else .claim.state=="CLOSED" end)
' "$reuse_report" >/dev/null

jq -e --slurpfile denominator "$denominator" '
  . as $report |
  all($denominator[0].proof_totals[];
    . as $proof | ([$report.cells[]|select(.proof_choice==$proof.proof_choice)]|length)==$proof.total) and
  all($denominator[0].indicator_totals[];
    . as $indicator | ([$report.cells[]|select(.indicator_class==$indicator.indicator_class)]|length)==$indicator.total)
' "$reuse_report" >/dev/null

case "$scenario" in
  normal)
    jq -e '.decision=="TEST_RECEIPT_REUSE_CLOSED" and .summary=={total:12,closed:12,unknown:0,refuted:0,direct_missing:0,dependency_blocked:0} and .reuse.producer_test_executions==1 and .reuse.receipt_reuses==1 and .reuse.consumer_test_executions==0 and .reuse.exact_scope_pairs==1 and .improvement.receipt_reuse_without_consumer_execution.state=="CLOSED"' "$reuse_report" >/dev/null
    ;;
  missing-receipt)
    jq -e '.decision=="TEST_RECEIPT_REUSE_UNKNOWN" and .summary=={total:12,closed:5,unknown:7,refuted:0,direct_missing:1,dependency_blocked:6} and .claim.reason=="TEST_RECEIPT_MISSING" and .claim.unknown_class=="DIRECT_MISSING" and .claim.blocked_by==[]' "$reuse_report" >/dev/null
    ;;
  stale-scope)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:8,unknown:0,refuted:4,direct_missing:0,dependency_blocked:0} and .claim.reason=="TEST_RECEIPT_SCOPE_MISMATCH"' "$reuse_report" >/dev/null
    ;;
  refuted-over-unknown)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:1,refuted:4,direct_missing:1,dependency_blocked:0} and .claim.state=="REFUTED" and .claim.reason=="TEST_RECEIPT_SCOPE_MISMATCH" and ([.cells[]|select(.id=="RECEIPT_IDENTITY" and .state=="UNKNOWN")]|length)==1' "$reuse_report" >/dev/null
    ;;
  authority-escalation)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:10,unknown:0,refuted:2,direct_missing:0,dependency_blocked:0} and .claim.reason=="TEST_RECEIPT_AUTHORITY_ESCALATED"' "$reuse_report" >/dev/null
    ;;
  unrecognized-decision)
    jq -e '.decision=="FAIL_CLOSED" and .summary=={total:12,closed:7,unknown:0,refuted:5,direct_missing:0,dependency_blocked:0} and .claim.reason=="UNRECOGNIZED_TEST_RECEIPT_DECISION" and .observation.receipt.decision=="FIXED_POINT"' "$reuse_report" >/dev/null
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 64
    ;;
esac

jq -S -n \
  --arg scenario "$scenario" \
  --arg subject_sha "$(jq -r '.subject_sha' "$reuse_report")" \
  --argjson verified_files "$verified" \
  --slurpfile reuse "$reuse_report" '
  {schema:"gooo/evidence-generator/test-receipt-reuse-conformance/v1",decision:"CONFORMANT",
   scenario:$scenario,subject_sha:$subject_sha,manifest:{verified:$verified_files,total:3},
   process:$reuse[0].summary,reuse:$reuse[0].reuse,claim:$reuse[0].claim}
' > "$report"
