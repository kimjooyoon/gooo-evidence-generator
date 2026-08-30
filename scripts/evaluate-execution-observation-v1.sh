#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: evaluate-execution-observation-v1.sh REPOSITORY DENOMINATOR OBSERVATION ACTIVITY_RESOLUTION OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
denominator=$2
observation=$3
activity_resolution=$4
output_arg=$5
subject_sha=$6
scenario=$7

repository_real=$(realpath "$repository")
output_real=$(realpath -m "$output_arg")
case "$output_real" in
  "$repository_real"|"$repository_real"/*)
    echo "output directory must be outside the source repository" >&2
    exit 65
    ;;
esac

if [ -n "$(find "$output_real" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null || true)" ]; then
  echo "output directory must be empty" >&2
  exit 66
fi
mkdir -p "$output_real"

jq -e --arg subject_sha "$subject_sha" '
  .schema=="gooo/evidence-generator/execution-observation/v1" and
  .subject_sha==$subject_sha and
  (.authority.graph_role=="meta_graph") and
  (.authority.graph_hash|type)=="string" and (.authority.source_digest|type)=="string" and
  (.authority.semantic_digest|type)=="string" and
  (.authority.activity_resolution_digest|type)=="string" and
  (.runner|type)=="object" and (.toolchain|type)=="object" and
  (.inputs|type)=="object" and (.stages|type)=="array" and
  ([.stages[].id]|unique|length)==(.stages|length) and
  (.not_applicable.product_build.status=="NOT_APPLICABLE" and .not_applicable.product_build.wall_ms==null and
   (.not_applicable.product_build.activity_id|type)=="string") and
  (.not_applicable.product_test.status=="NOT_APPLICABLE" and .not_applicable.product_test.wall_ms==null and
   (.not_applicable.product_test.activity_id|type)=="string") and
  (.activity_refs|type)=="array" and (.activity_refs|length)==12 and
  ([.activity_refs[].cell_id]|unique|length)==12 and
  all(.activity_refs[]; (.graph_role=="meta_graph") and (.activity_resolution_digest|type)=="string")
' "$observation" >/dev/null
jq -e '
  .schema=="gooo/evidence-generator/execution-observation-denominator/v1" and
  .target_cells==12 and (.cells|length)==12 and
  ([.cells[].ordinal]==[range(1;13)]) and
  ([.cells[].id]|unique|length)==12 and
  ([.cells[].activity]|unique|length)==12 and
  ([.proof_totals[].total]|add)==12 and ([.indicator_totals[].total]|add)==12
' "$denominator" >/dev/null
jq -e '
  .schema_version=="gooo-graph/v1" and
  .activity_resolution_observation.schema=="gooo/evidence-generator/activity-resolution-observation/v1" and
  .activity_resolution_observation.role=="meta_graph" and
  .ir.status=="available"
' "$activity_resolution" >/dev/null

resolution_digest=$(jq -S -c . "$activity_resolution" | sha256sum | awk '{print $1}')
graph_hash=$(jq -r '.graph_hash' "$activity_resolution")
core_tag=$(jq -r '.activity_resolution_observation.core_release.tag' "$activity_resolution")
core_target=$(jq -r '.activity_resolution_observation.core_release.target_commit_sha' "$activity_resolution")
core_binary_digest=$(jq -r '.activity_resolution_observation.core_release.binary_sha256' "$activity_resolution")

activity_bindings=$(jq -c '
  [ .activity_resolution_observation.entries[] |
    select(.receipt.decision=="CLOSED") |
    {id,activity,source_digest:.receipt.subject.source_digest,semantic_digest:.receipt.subject.semantic_digest}
  ]
' "$activity_resolution")

overrides=$(jq -S -n \
  --arg resolution_digest "$resolution_digest" \
  --arg graph_hash "$graph_hash" \
  --arg core_tag "$core_tag" \
  --arg core_target "$core_target" \
  --arg core_binary_digest "$core_binary_digest" \
  --argjson bindings "$activity_bindings" \
  --slurpfile denominator "$denominator" \
  --slurpfile observation "$observation" '
  ($denominator[0]) as $d |
  ($observation[0]) as $o |
  def stage($id): ([$o.stages[] | select(.id==$id)][0] // null);
  def binding($id;$activity):
    any($bindings[]; .id==$id and .activity==$activity);
  def string_field($value): ($value|type)=="string" and ($value|length)>0;
  def digest_field($value): if ($value|type)=="string" then ($value|test("^[0-9a-f]{64}$")) else false end;
  def integer_field($value): if ($value|type)=="number" then (($value|floor)==$value and $value>=0) else false end;
  def unknown($cell;$reason;$next;$class):
    {cell_id:$cell.id,state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:$reason,
     unknown_class:$class,next_operation:$next,blocked_by:[]};
  def refuted($cell;$reason;$next):
    {cell_id:$cell.id,state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:$reason,
     unknown_class:null,next_operation:$next,blocked_by:[]};
  def closed($cell;$reason):
    {cell_id:$cell.id,state:"CLOSED",stage:$cell.stage,step:$cell.step,reason:$reason,
     unknown_class:null,next_operation:"NONE",blocked_by:[]};
  def valid_stage_identity($s):
    ($s!=null and string_field($s.activity_id) and string_field($s.activity) and
     digest_field($s.runner_digest) and digest_field($s.toolchain_digest) and
     digest_field($s.input_digest) and digest_field($s.activity_resolution_digest) and
     $s.activity_resolution_digest==$resolution_digest and binding($s.activity_id;$s.activity));
  def valid_peak($s):
    ($s.peak_rss_kib_available|type)=="boolean" and
    (if $s.peak_rss_kib_available then integer_field($s.peak_rss_kib) else $s.peak_rss_kib==null end);
  def valid_cache($s):
    ($s.cache|type)=="object" and string_field($s.cache.state) and
    ($s.cache.key==null or string_field($s.cache.key)) and
    ($s.cache.digest==null or digest_field($s.cache.digest)) and
    string_field($s.cache.authority);
  def valid_executed($s):
    ($s.status=="EXECUTED" and integer_field($s.wall_ms) and digest_field($s.result_digest) and
     valid_stage_identity($s) and valid_peak($s) and valid_cache($s));
  def valid_reused($s):
    ($s.status=="REUSED" and $s.wall_ms==null and $s.peak_rss_kib==null and
     $s.peak_rss_kib_available==false and valid_stage_identity($s) and valid_cache($s) and
     ($s.reuse_receipt|type)=="object" and $s.reuse_receipt.decision=="PASS" and
     digest_field($s.reuse_receipt.digest) and string_field($s.reuse_receipt.producer_stage_id) and
     $s.reuse_receipt.consumer_executions==0);
  def own($cell):
    if $cell.id=="RELEASED_EXECUTION_CORE" then
      if string_field($o.authority.core_release.tag) and
         $o.authority.core_release.tag==$core_tag and
         $o.authority.core_release.target_commit_sha==$core_target and
         $o.authority.core_release.binary_sha256==$core_binary_digest and
         $o.authority.activity_resolution_digest==$resolution_digest then
        closed($cell;"RELEASED_EXECUTION_CORE_OBSERVED")
      elif ($o.authority.core_release|type)!="object" or
           (string_field($o.authority.core_release.tag)|not) or
           (string_field($o.authority.activity_resolution_digest)|not) then
        unknown($cell;"RELEASED_EXECUTION_CORE_UNAVAILABLE";"RESTORE_RELEASED_EXECUTION_CORE";"DIRECT_MISSING")
      else
        refuted($cell;"RELEASED_EXECUTION_CORE_CONTRADICTION";"RESTORE_RELEASED_EXECUTION_CORE_IDENTITY")
      end
    elif $cell.id=="META_ACTIVITY_AUTHORITY" then
      if ($o.authority.activity_resolution_digest==$resolution_digest and
          ($bindings|length)==12 and all($o.stages[]; valid_stage_identity(.))) then
        closed($cell;"EXECUTION_OBSERVATION_ACTIVITIES_BOUND")
      elif ($bindings|length)<12 then
        unknown($cell;"EXECUTION_OBSERVATION_ACTIVITY_RECEIPT_UNAVAILABLE";"RESTORE_ACTIVITY_RESOLUTION_RECEIPTS";"DIRECT_MISSING")
      else
        refuted($cell;"EXECUTION_OBSERVATION_ACTIVITY_AUTHORITY_CONTRADICTION";"RESTORE_ACTIVITY_AUTHORITY")
      end
    elif $cell.id=="RUNNER_TOOLCHAIN" then
      if string_field($o.runner.name) and string_field($o.runner.os) and string_field($o.runner.arch) and
         string_field($o.runner.image) and string_field($o.toolchain.go) and
         string_field($o.toolchain.gooo.tag) and digest_field($o.toolchain.gooo.binary_sha256) then
        closed($cell;"RUNNER_AND_TOOLCHAIN_PINNED")
      else
        unknown($cell;"RUNNER_OR_TOOLCHAIN_UNAVAILABLE";"RESTORE_RUNNER_AND_TOOLCHAIN_IDENTITY";"DIRECT_MISSING")
      end
    elif $cell.id=="INPUT_DIGEST" then
      if digest_field($o.inputs.scope_digest) and
         ($o.stages|length)==3 and all($o.stages[]; .input_digest==$o.inputs.scope_digest) then
        closed($cell;"EXECUTION_INPUT_DIGEST_PINNED")
      elif (digest_field($o.inputs.scope_digest)|not) then
        unknown($cell;"EXECUTION_INPUT_DIGEST_UNAVAILABLE";"RESTORE_EXECUTION_INPUT_DIGEST";"DIRECT_MISSING")
      else
        refuted($cell;"EXECUTION_INPUT_DIGEST_MISMATCH";"RESTORE_EXACT_EXECUTION_INPUT_SCOPE")
      end
    elif $cell.id=="BUILD_STAGE" then
      (stage("EVIDENCE_BUILD")) as $s |
      if $s==null then unknown($cell;"BUILD_STAGE_NOT_EXECUTED";"EXECUTE_BUILD_STAGE";"DIRECT_MISSING")
      elif $s.status=="EXECUTED" and valid_executed($s) then closed($cell;"BUILD_STAGE_EXECUTION_OBSERVED")
      elif ($s.status=="NOT_EXECUTED" or $s.status=="UNKNOWN") and $s.wall_ms==null then unknown($cell;"BUILD_STAGE_NOT_EXECUTED";"EXECUTE_BUILD_STAGE";"DIRECT_MISSING")
      elif $s.status=="REUSED" then refuted($cell;"BUILD_STAGE_REUSE_NOT_AUTHORIZED";"EXECUTE_BUILD_STAGE")
      else refuted($cell;"BUILD_STAGE_OBSERVATION_INVALID";"RESTORE_BUILD_STAGE_RECEIPT") end
    elif $cell.id=="TEST_STAGE" then
      (stage("SEMANTIC_TEST")) as $s |
      if $s==null then unknown($cell;"TEST_STAGE_NOT_EXECUTED";"EXECUTE_TEST_STAGE";"DIRECT_MISSING")
      elif $s.status=="EXECUTED" and valid_executed($s) then closed($cell;"TEST_STAGE_EXECUTION_OBSERVED")
      elif ($s.status=="NOT_EXECUTED" or $s.status=="UNKNOWN") and $s.wall_ms==null then unknown($cell;"TEST_STAGE_NOT_EXECUTED";"EXECUTE_TEST_STAGE";"DIRECT_MISSING")
      elif $s.status=="REUSED" then refuted($cell;"TEST_STAGE_REUSE_REQUIRES_RECEIPT";"EXECUTE_TEST_STAGE")
      else refuted($cell;"TEST_STAGE_OBSERVATION_INVALID";"RESTORE_TEST_STAGE_RECEIPT") end
    elif $cell.id=="CACHE_IDENTITY" then
      (stage("VERIFIED_TEST_RECEIPT_REUSE")) as $s |
      if $s==null or ($s.cache|type)!="object" then unknown($cell;"CACHE_IDENTITY_UNAVAILABLE";"PROVIDE_CACHE_KEY_DIGEST_AND_AUTHORITY";"DIRECT_MISSING")
      elif $s.cache.state=="HIT" and string_field($s.cache.key) and digest_field($s.cache.digest) and
           string_field($s.cache.authority) and $s.cache.digest==($s.reuse_receipt.digest // "") and
           ($s.cache.key|startswith("test-receipt:")) then closed($cell;"CACHE_KEY_DIGEST_AND_AUTHORITY_VERIFIED")
      elif $s.cache.state=="UNKNOWN" or $s.cache.key==null or $s.cache.digest==null or $s.cache.authority==null then unknown($cell;"CACHE_IDENTITY_UNAVAILABLE";"PROVIDE_CACHE_KEY_DIGEST_AND_AUTHORITY";"DIRECT_MISSING")
      else refuted($cell;"CACHE_IDENTITY_MISMATCH";"RESTORE_CACHE_KEY_DIGEST_AND_AUTHORITY") end
    elif $cell.id=="REUSED_WORK" then
      (stage("VERIFIED_TEST_RECEIPT_REUSE")) as $s | (stage("SEMANTIC_TEST")) as $test |
      if $s==null or $s.reuse_receipt==null then unknown($cell;"VERIFIED_REUSE_UNAVAILABLE";"PROVIDE_EXACT_REUSE_RECEIPT";"DIRECT_MISSING")
      elif valid_reused($s) and $s.reuse_receipt.producer_stage_id=="SEMANTIC_TEST" and
           $s.reuse_receipt.input_digest==$test.input_digest and
           $s.reuse_receipt.result_digest==$test.result_digest and
           $s.reuse_receipt.activity_resolution_digest==$resolution_digest then closed($cell;"VERIFIED_WORK_REUSED")
      elif $s.status=="NOT_EXECUTED" or $s.status=="UNKNOWN" then unknown($cell;"VERIFIED_REUSE_UNAVAILABLE";"PROVIDE_EXACT_REUSE_RECEIPT";"DIRECT_MISSING")
      else refuted($cell;"VERIFIED_REUSE_RECEIPT_CONTRADICTION";"RESTORE_EXACT_REUSE_RECEIPT") end
    elif $cell.id=="NOT_EXECUTED_STATE" then
      if all($o.stages[]; ((.status=="EXECUTED" and (.wall_ms|type)=="number") or
         ((.status=="REUSED" or .status=="NOT_EXECUTED" or .status=="UNKNOWN") and .wall_ms==null))) and
         ($o.authority.consumer_test_executions==0) then closed($cell;"NOT_EXECUTED_WORK_NOT_COUNTED_AS_SUCCESS")
      elif any($o.stages[]; ((.status=="REUSED" or .status=="NOT_EXECUTED" or .status=="UNKNOWN") and .wall_ms!=null)) then
        refuted($cell;"NOT_EXECUTED_WORK_HAS_SYNTHETIC_WALL_TIME";"REMOVE_SYNTHETIC_ZERO_MILLISECONDS")
      else unknown($cell;"NOT_EXECUTED_STATE_UNAVAILABLE";"DECLARE_EXECUTION_STATUS_AND_WALL_TIME";"DIRECT_MISSING") end
    elif $cell.id=="PEAK_RSS" then
      if all($o.stages[]; valid_peak(.)) then closed($cell;"PEAK_RSS_AVAILABILITY_EXPLICIT")
      elif any($o.stages[]; (.peak_rss_kib_available|type)!="boolean") then unknown($cell;"PEAK_RSS_AVAILABILITY_UNAVAILABLE";"DECLARE_PEAK_RSS_AVAILABILITY";"DIRECT_MISSING")
      else refuted($cell;"PEAK_RSS_AVAILABILITY_CONTRADICTION";"RESTORE_PEAK_RSS_RECEIPT") end
    elif $cell.id=="IMPROVEMENT_BOUNDARY" then
      unknown($cell;"EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT";"RUN_EXACT_BEFORE_AND_AFTER_PAIR";"DIRECT_MISSING")
    elif $cell.id=="HUMAN_DOSSIER" then
      closed($cell;"EXECUTION_OBSERVATION_HUMAN_DOSSIER_PUBLISHED")
    else
      refuted($cell;"UNKNOWN_DENOMINATOR_CELL";"RESTORE_EXECUTION_OBSERVATION_DENOMINATOR")
    end;
  def resolve($id):
    ($d.cells[]|select(.id==$id)) as $cell |
    (own($cell)) as $direct |
    if $direct.state=="UNKNOWN" or $direct.state=="REFUTED" then $direct
    elif ($cell.depends_on|length)==0 then $direct
    else
      ([$cell.depends_on[]|resolve(.)]) as $deps |
      if any($deps[]; .state=="REFUTED") then
        {cell_id:$cell.id,state:"REFUTED",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_REFUTED",unknown_class:null,next_operation:"RESOLVE_REFUTED_PREDECESSORS",blocked_by:[$deps[]|select(.state=="REFUTED")|.cell_id]}
      elif any($deps[]; .state=="UNKNOWN") then
        {cell_id:$cell.id,state:"UNKNOWN",stage:$cell.stage,step:$cell.step,reason:"DEPENDENCY_BLOCKED",unknown_class:"DEPENDENCY_BLOCKED",next_operation:"RESOLVE_UNKNOWN_PREDECESSORS",blocked_by:[$deps[]|select(.state=="UNKNOWN")|.cell_id]}
      else $direct end
    end;
  {cells:[$d.cells[]|. as $cell|($cell + resolve($cell.id))],bindings:$bindings}
' )

jq -S -n \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --arg resolution_digest "$resolution_digest" \
  --arg graph_hash "$graph_hash" \
  --slurpfile observation "$observation" \
  --slurpfile resolution "$activity_resolution" \
  --argjson evaluation "$overrides" '
  ($observation[0]) as $o |
  ($resolution[0]) as $r |
  ($evaluation.cells) as $cells |
  ([$cells[]|select(.state=="CLOSED")]|length) as $closed |
  ([$cells[]|select(.state=="UNKNOWN")]|length) as $unknown |
  ([$cells[]|select(.state=="REFUTED")]|length) as $refuted |
  ([$cells[]|select(.unknown_class=="DIRECT_MISSING")]|length) as $direct_missing |
  ([$cells[]|select(.unknown_class=="DEPENDENCY_BLOCKED")]|length) as $dependency_blocked |
  ([$cells[]|select(.state!="CLOSED")][0] // null) as $first_nonclosed |
  ([$cells[]|select(.state=="REFUTED" and .reason!="DEPENDENCY_REFUTED")][0] //
   [$cells[]|select(.state=="REFUTED")][0] // null) as $first_refuted |
  {
    schema:"gooo/evidence-generator/execution-observation-report/v1",
    decision:(if $refuted>0 then "FAIL_CLOSED" elif $unknown>0 then "INCOMPLETE" else "EXECUTION_OBSERVED" end),
    subject_sha:$subject_sha,
    scenario:$scenario,
    graph:{role:$o.authority.graph_role,hash:$graph_hash,source_digest:$o.authority.source_digest,
      semantic_digest:$o.authority.semantic_digest,activity_resolution_digest:$resolution_digest,
      activity_resolution_summary:$r.activity_resolution_observation.summary},
    runner:$o.runner,
    toolchain:$o.toolchain,
    inputs:$o.inputs,
    stages:$o.stages,
    summary:{total:($cells|length),closed:$closed,unknown:$unknown,refuted:$refuted,
      direct_missing:$direct_missing,dependency_blocked:$dependency_blocked},
    cells:$cells,
    reuse:{status:($o.stages[]|select(.id=="VERIFIED_TEST_RECEIPT_REUSE")|.status),
      producer_test_executions:1,consumer_test_executions:$o.authority.consumer_test_executions,
      receipt_reuses:(if ([$cells[]|select(.id=="REUSED_WORK" and .state=="CLOSED")]|length)==1 then 1 else 0 end),
      cache:($o.stages[]|select(.id=="VERIFIED_TEST_RECEIPT_REUSE")|.cache),
      receipt_digest:($o.stages[]|select(.id=="VERIFIED_TEST_RECEIPT_REUSE")|.reuse_receipt.digest)},
    performance:{build:($o.stages[]|select(.id=="EVIDENCE_BUILD")|{status,wall_ms,peak_rss_kib}),
      test:($o.stages[]|select(.id=="SEMANTIC_TEST")|{status,wall_ms,peak_rss_kib}),
      reused:($o.stages[]|select(.id=="VERIFIED_TEST_RECEIPT_REUSE")|{status,wall_ms,peak_rss_kib}),
      improvement:{build_wall_ms:{state:"UNKNOWN",before:($o.stages[]|select(.id=="EVIDENCE_BUILD")|.wall_ms),after:null,reason:"EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT"},
        test_wall_ms:{state:"UNKNOWN",before:($o.stages[]|select(.id=="SEMANTIC_TEST")|.wall_ms),after:null,reason:"EQUIVALENT_BEFORE_AFTER_PAIR_ABSENT"}}},
    authority:($o.authority + {measurement_source:"DIRECT_COMMAND_RECEIPT",log_parsing_authority:false,
      source_repository_writes:0,local_test_executions:0,denominator_changes:0}),
    claim:(if $first_refuted!=null then
      {state:"REFUTED",stage:$first_refuted.stage,step:$first_refuted.step,reason:$first_refuted.reason,
       unknown_class:null,next_operation:$first_refuted.next_operation,blocked_by:$first_refuted.blocked_by}
    elif $first_nonclosed!=null then
      {state:"UNKNOWN",stage:$first_nonclosed.stage,step:$first_nonclosed.step,reason:$first_nonclosed.reason,
       unknown_class:$first_nonclosed.unknown_class,next_operation:$first_nonclosed.next_operation,blocked_by:$first_nonclosed.blocked_by}
    else
      {state:"CLOSED",stage:null,step:null,reason:"EXECUTION_OBSERVATION_CONFORMED",unknown_class:null,next_operation:"PUBLISH_EXECUTION_HUMAN_DOSSIER",blocked_by:[]}
    end)
  }
' > "$output_real/evaluation.json"

cp "$observation" "$output_real/observation.json"
decision=$(jq -r '.decision' "$output_real/evaluation.json")
build_status=$(jq -r '.performance.build.status' "$output_real/evaluation.json")
build_wall_ms=$(jq -r '.performance.build.wall_ms // "NOT_EXECUTED"' "$output_real/evaluation.json")
test_status=$(jq -r '.performance.test.status' "$output_real/evaluation.json")
test_wall_ms=$(jq -r '.performance.test.wall_ms // "NOT_EXECUTED"' "$output_real/evaluation.json")
reuse_status=$(jq -r '.reuse.status' "$output_real/evaluation.json")
reuse_count=$(jq -r '.reuse.receipt_reuses' "$output_real/evaluation.json")
cat > "$output_real/report.md" <<EOF
# Execution observation v1

- scenario: $scenario
- decision: $decision
- evidence-build stage: $build_status, $build_wall_ms ms
- semantic-test stage: $test_status, $test_wall_ms ms
- verified reuse: $reuse_status, $reuse_count/1 receipt reuse
- build/test improvement: UNKNOWN until an exact before/after pair exists
- activity authority: released semantic graph $graph_hash
- activity-resolution digest: $resolution_digest
EOF

tracked_files=(observation.json evaluation.json report.md)
entries='[]'
for relative_path in "${tracked_files[@]}"; do
  digest=$(sha256sum "$output_real/$relative_path" | awk '{print $1}')
  size=$(wc -c < "$output_real/$relative_path" | tr -d ' ')
  entries=$(jq -c --arg path "$relative_path" --arg sha256 "$digest" --argjson size "$size" '. + [{path:$path,sha256:$sha256,size_bytes:$size}]' <<<"$entries")
done
jq -S -n --arg subject_sha "$subject_sha" --arg scenario "$scenario" --argjson files "$entries" '
  {schema:"gooo/evidence-generator/execution-observation-manifest/v1",subject_sha:$subject_sha,
   scenario:$scenario,tracked_file_count:($files|length),files:$files}
' > "$output_real/manifest.json"

test "$(find "$output_real" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 4
