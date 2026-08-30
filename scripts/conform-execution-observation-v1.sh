#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 6 ]; then
  echo "usage: conform-execution-observation-v1.sh OUTPUT DENOMINATOR ACTIVITY_RESOLUTION SCENARIO SUBJECT_SHA REPORT" >&2
  exit 64
fi

output=$(realpath "$1")
denominator=$2
activity_resolution=$3
scenario=$4
subject_sha=$5
report=$6

expected_files=(evaluation.json manifest.json observation.json report.md)
test "$(find "$output" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
for relative_path in "${expected_files[@]}"; do test -f "$output/$relative_path"; done

manifest="$output/manifest.json"
evaluation="$output/evaluation.json"
observation="$output/observation.json"
jq -e --arg subject_sha "$subject_sha" --arg scenario "$scenario" '
  .schema=="gooo/evidence-generator/execution-observation-manifest/v1" and
  .subject_sha==$subject_sha and .scenario==$scenario and
  .tracked_file_count==3 and (.files|length)==3
' "$manifest" >/dev/null
verified=0
while IFS=$'\t' read -r relative_path expected_digest expected_size; do
  case "$relative_path" in /*|*..*) exit 65 ;; esac
  test "$(sha256sum "$output/$relative_path" | awk '{print $1}')" = "$expected_digest"
  test "$(wc -c < "$output/$relative_path" | tr -d ' ')" -eq "$expected_size"
  verified=$((verified+1))
done < <(jq -r '.files[]|[.path,.sha256,.size_bytes]|@tsv' "$manifest")
test "$verified" -eq 3

resolution_digest=$(jq -S -c . "$activity_resolution" | sha256sum | awk '{print $1}')
jq -e --arg subject_sha "$subject_sha" --arg scenario "$scenario" --arg resolution_digest "$resolution_digest" '
  .schema=="gooo/evidence-generator/execution-observation-report/v1" and
  .subject_sha==$subject_sha and .scenario==$scenario and
  .graph.activity_resolution_digest==$resolution_digest and
  .summary.total==12 and .summary.closed+.summary.unknown+.summary.refuted==12 and
  all(.cells[];
    (.cell_id|type)=="string" and (.state|IN("CLOSED","UNKNOWN","REFUTED")) and
    (.stage|type)=="string" and (.step|type)=="string" and (.reason|type)=="string" and
    (.blocked_by|type)=="array" and
    (if .state=="UNKNOWN" then (.unknown_class|type)=="string" and (.next_operation|type)=="string" else true end)) and
  all(.stages[];
    (.status|IN("EXECUTED","REUSED","NOT_EXECUTED","UNKNOWN")) and
    (if .status=="EXECUTED" then (.wall_ms|type)=="number" and (.wall_ms|floor)==.wall_ms and .wall_ms>=0
     else .wall_ms==null end) and
    (.peak_rss_kib_available|type)=="boolean" and
    (if .peak_rss_kib_available then (.peak_rss_kib|type)=="number" and (.peak_rss_kib|floor)==.peak_rss_kib and .peak_rss_kib>=0 else .peak_rss_kib==null end) and
    (.cache|type)=="object" and (.cache.authority|type)=="string" and (.cache.authority|length)>0)
' "$evaluation" >/dev/null

jq -e --arg subject_sha "$subject_sha" '
  .schema=="gooo/evidence-generator/execution-observation/v1" and
  .subject_sha==$subject_sha and (.authority.activity_resolution_digest|type)=="string" and
  (.not_applicable.product_build.status=="NOT_APPLICABLE" and .not_applicable.product_build.wall_ms==null) and
  (.not_applicable.product_test.status=="NOT_APPLICABLE" and .not_applicable.product_test.wall_ms==null) and
  (.activity_refs|type)=="array" and (.activity_refs|length)==12 and
  ([.activity_refs[].cell_id]|unique|length)==12 and
  all(.stages[]; (.activity_id|type)=="string" and (.activity|type)=="string" and
    (.runner_digest|test("^[0-9a-f]{64}$")) and (.toolchain_digest|test("^[0-9a-f]{64}$")) and
    (.input_digest|test("^[0-9a-f]{64}$")))
' "$observation" >/dev/null

jq -e --slurpfile denominator "$denominator" '
  . as $report |
  all($denominator[0].proof_totals[];
    . as $proof | ([$report.cells[]|select(.proof_choice==$proof.proof_choice)]|length)==$proof.total) and
  all($denominator[0].indicator_totals[];
    . as $indicator | ([$report.cells[]|select(.indicator_class==$indicator.indicator_class)]|length)==$indicator.total)
' "$evaluation" >/dev/null

case "$scenario" in
  normal)
    jq -e '
      .decision=="INCOMPLETE" and .summary=={total:12,closed:11,unknown:1,refuted:0,direct_missing:1,dependency_blocked:0} and
      .performance.build.status=="EXECUTED" and (.performance.build.wall_ms|type)=="number" and
      .performance.test.status=="EXECUTED" and (.performance.test.wall_ms|type)=="number" and
      .reuse.status=="REUSED" and .reuse.receipt_reuses==1 and .reuse.consumer_test_executions==0 and
      .performance.improvement.build_wall_ms.state=="UNKNOWN" and .performance.improvement.test_wall_ms.state=="UNKNOWN" and
      .claim.state=="UNKNOWN" and .claim.reason=="EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT"
    ' "$evaluation" >/dev/null
    ;;
  not-executed)
    jq -e '
      .decision=="INCOMPLETE" and .summary.refuted==0 and .summary.unknown>0 and
      ([.stages[]|select(.status!="EXECUTED" and .wall_ms!=null)]|length)==0 and
      ([.cells[]|select(.state=="UNKNOWN" and .reason=="BUILD_STAGE_NOT_EXECUTED")]|length)==1 and
      ([.cells[]|select(.state=="UNKNOWN" and .reason=="TEST_STAGE_NOT_EXECUTED")]|length)==1 and
      .claim.state=="UNKNOWN"
    ' "$evaluation" >/dev/null
    ;;
  missing-reuse)
    jq -e '
      .decision=="INCOMPLETE" and .summary.refuted==0 and .summary.unknown>0 and
      .reuse.status=="UNKNOWN" and .reuse.receipt_reuses==0 and
      ([.cells[]|select(.state=="UNKNOWN" and .reason=="CACHE_IDENTITY_UNAVAILABLE")]|length)==1 and
      .claim.state=="UNKNOWN"
    ' "$evaluation" >/dev/null
    ;;
  stale-cache)
    jq -e '
      .decision=="FAIL_CLOSED" and .summary.refuted>0 and .summary.unknown>0 and
      .claim.state=="REFUTED" and .claim.reason=="CACHE_IDENTITY_MISMATCH" and
      ([.cells[]|select(.state=="UNKNOWN" and .reason=="EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT")]|length)==1
    ' "$evaluation" >/dev/null
    ;;
  mixed)
    jq -e '
      .decision=="FAIL_CLOSED" and .summary.refuted>0 and .summary.unknown>0 and
      .claim.state=="REFUTED" and
      ([.cells[]|select(.state=="UNKNOWN" and .reason=="EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT")]|length)==1
    ' "$evaluation" >/dev/null
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 64
    ;;
esac

jq -S -n \
  --arg scenario "$scenario" \
  --arg subject_sha "$subject_sha" \
  --argjson verified_files "$verified" \
  --slurpfile evaluation "$evaluation" '
  {schema:"gooo/evidence-generator/execution-observation-conformance/v1",decision:"CONFORMANT",
   scenario:$scenario,subject_sha:$subject_sha,manifest:{verified:$verified_files,total:3},
   summary:$evaluation[0].summary,claim:$evaluation[0].claim,
   performance:$evaluation[0].performance,reuse:$evaluation[0].reuse}
' > "$report"
