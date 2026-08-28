#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 9 ]; then
  echo "usage: generate.sh REPOSITORY META_GRAPH PROJECT_GRAPH DENOMINATOR OBSERVATION PROFILE OUTPUT SUBJECT_SHA SCENARIO" >&2
  exit 64
fi

repository=$1
meta_graph=$2
project_graph=$3
denominator=$4
observation=$5
profile=$6
output_arg=$7
subject_sha=$8
scenario=$9

repository_real=$(realpath "$repository")
output_real=$(realpath -m "$output_arg")
case "$output_real" in
  "$repository_real"|"$repository_real"/*)
    echo "output directory must be outside the source repository" >&2
    exit 65
    ;;
esac

mkdir -p "$output_real"
if [ -n "$(find "$output_real" -mindepth 1 -maxdepth 1 -print -quit)" ]; then
  echo "output directory must be empty" >&2
  exit 66
fi

jq -e '
  .schema == "gooo/evidence-generator/denominator/v1" and
  .target_cells > 0 and .target_cells == (.cells | length) and
  ([.cells[].ordinal] == [range(1; .target_cells + 1)]) and
  (([.cells[].id] | unique | length) == .target_cells) and
  (([.cells[].activity] | unique | length) == .target_cells) and
  ([.proof_totals[].proof_choice] | sort) == ["COHERENCE","FOUNDATION","REGRESSION"] and
  ([.proof_totals[].total] | add) == .target_cells
' "$denominator" >/dev/null

jq -e '
  .schema == "gooo/evidence-generator/repetition-observation/v1" and
  .observed_projects == (.sources | length) and
  .promotion_threshold == 3 and .observed_projects == 4 and
  all(.patterns[];
    .support_count == (.source_indices | length) and
    .support_count <= 4 and .support_count >= 0 and
    ((.source_indices | unique | length) == (.source_indices | length)))
' "$observation" >/dev/null

jq -e '
  .schema == "gooo/evidence-generator/project/v2" and
  .graph_roles == {promotion:"meta_graph",cells:"project_graph"} and
  .expected_output_files == 7 and
  ((.required_patterns | unique | length) == (.required_patterns | length)) and
  ((.conformance_checks | length) == 8) and
  ((.scenarios | length) == 6)
' "$profile" >/dev/null

jq -e '.schema_version == "gooo-graph/v1" and (.nodes | type) == "array"' "$meta_graph" >/dev/null
jq -e '.schema_version == "gooo-graph/v1" and (.nodes | type) == "array"' "$project_graph" >/dev/null
jq -e '
  (.schema | type) == "string" and (.schema | endswith("/core-release-lock/v1")) and
  (.repository | type) == "string" and (.repository | length) > 0 and
  (.tag | type) == "string" and (.tag | length) > 0 and
  (.tag_object_sha | type) == "string" and (.tag_object_sha | test("^[0-9a-f]{40,64}$")) and
  (.target_commit_sha | type) == "string" and (.target_commit_sha | test("^[0-9a-f]{40,64}$")) and
  (.assets | type) == "array" and (.assets | length) > 0 and
  all(.assets[];
    (.name | type) == "string" and (.name | length) > 0 and
    (.sha256 | type) == "string" and (.sha256 | test("^[0-9a-f]{64}$"))) and
  any(.assets[]; .name == "gooo-linux-amd64.tar.gz")
' "$repository/contracts/core-release-lock-v1.json" >/dev/null

mkdir -p \
  "$output_real/contracts" \
  "$output_real/meta" \
  "$output_real/conformance" \
  "$output_real/docs"

jq -S . "$repository/contracts/core-release-lock-v1.json" > "$output_real/contracts/core-release-lock-v1.json"
jq -S . "$denominator" > "$output_real/contracts/evidence-denominator-v1.json"

jq -S -n \
  --slurpfile meta_graph "$meta_graph" \
  --slurpfile project_graph "$project_graph" \
  --slurpfile denominator "$denominator" \
  --slurpfile observation "$observation" \
  --slurpfile profile "$profile" \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" '
  ($meta_graph[0]) as $meta |
  ($project_graph[0]) as $project |
  ($denominator[0]) as $d |
  ($observation[0]) as $o |
  ($profile[0]) as $p |
  def meta_occurrences($name):
    if $name == null then 0
    else ([$meta.nodes[]? | select(.kind == "Activity" and .name == $name)] | length)
    end;
  def project_occurrences($name):
    if $name == null then 0
    else ([$project.nodes[]? | select(.kind == "Activity" and .name == $name)] | length)
    end;
  ([$o.patterns[] |
    . as $pattern |
    (meta_occurrences($pattern.meta_activity)) as $activity_occurrences |
    ($pattern.support_count >= $o.promotion_threshold) as $support_eligible |
    ($pattern.meta_activity != null and $activity_occurrences == 1) as $meta_bound |
    {
      id: $pattern.id,
      support_count: $pattern.support_count,
      support_total: $o.observed_projects,
      support_eligible: $support_eligible,
      meta_activity: $pattern.meta_activity,
      meta_activity_occurrences: $activity_occurrences,
      meta_bound: $meta_bound,
      promoted: ($support_eligible and $meta_bound),
      generator_role: $pattern.generator_role
    }
  ]) as $patterns |
  ([$p.required_patterns[] as $required |
    select(([$patterns[] | select(.id == $required and .promoted)] | length) == 0) |
    $required
  ]) as $missing_required |
  ([$missing_required[] as $required |
    $patterns[] |
    select(.id == $required and .support_eligible and
      .meta_activity != null and .meta_activity_occurrences == 0) |
    .id
  ]) as $unknown_required |
  ($missing_required - $unknown_required) as $refuted_required |
  (reduce $d.cells[] as $cell
    ({cells: [], decisions: {}};
      . as $acc |
      (project_occurrences($cell.activity)) as $activity_occurrences |
      ([$cell.depends_on[]? | $acc.decisions[.]]) as $dependencies |
      (if $activity_occurrences == 0 then
        {cell_id: $cell.id, state: "UNKNOWN", reason: $cell.unknown_reason,
         next_operation: $cell.next_operation, unknown_class: "DIRECT_MISSING", blocked_by: []}
      elif $activity_occurrences > 1 then
        {cell_id: $cell.id, state: "REFUTED", reason: "AMBIGUOUS_ACTIVITY_BINDING",
         next_operation: "REMOVE_DUPLICATE_GOOO_ACTIVITY", unknown_class: null, blocked_by: []}
      elif any($dependencies[]; .state == "REFUTED") then
        {cell_id: $cell.id, state: "REFUTED", reason: "DEPENDENCY_REFUTED",
         next_operation: "RESOLVE_REFUTED_PREDECESSORS", unknown_class: null,
         blocked_by: [$dependencies[] | select(.state == "REFUTED") | .cell_id]}
      elif any($dependencies[]; .state == "UNKNOWN") then
        {cell_id: $cell.id, state: "UNKNOWN", reason: "DEPENDENCY_BLOCKED",
         next_operation: "RESOLVE_UNKNOWN_PREDECESSORS", unknown_class: "DEPENDENCY_BLOCKED",
         blocked_by: [$dependencies[] | select(.state == "UNKNOWN") | .cell_id]}
      else
        {cell_id: $cell.id, state: "CLOSED", reason: $cell.closed_reason,
         next_operation: "NONE", unknown_class: null, blocked_by: []}
      end) as $decision |
      .cells += [$cell + $decision + {activity_occurrences: $activity_occurrences}] |
      .decisions[$cell.id] = $decision
    )
  ) as $evaluation |
  ([$evaluation.cells[] | select(.state == "CLOSED")] | length) as $closed |
  ([$evaluation.cells[] | select(.state == "UNKNOWN")] | length) as $unknown |
  ([$evaluation.cells[] | select(.state == "REFUTED")] | length) as $refuted |
  ([$evaluation.cells[] | select(.unknown_class == "DIRECT_MISSING")] | length) as $direct_missing |
  ([$evaluation.cells[] | select(.unknown_class == "DEPENDENCY_BLOCKED")] | length) as $dependency_blocked |
  ([$evaluation.cells[] | select(.state != "CLOSED")][0] // null) as $first_nonclosed |
  {
    schema: "gooo/evidence-generator/report/v2",
    decision: (if ($refuted_required | length) > 0 or $refuted > 0 then "FAIL_CLOSED"
      elif ($unknown_required | length) > 0 or $unknown > 0 then "INCOMPLETE"
      else "PROJECT_GENERATED" end),
    scenario: $scenario,
    subject: {
      sha: $subject_sha,
      project_id: $p.id,
      meta_graph_hash: $meta.graph_hash,
      meta_source_digest: $meta.source_digest,
      project_graph_hash: $project.graph_hash,
      project_source_digest: $project.source_digest
    },
    authority: {
      activity_binding: "RELEASED_GOOO_GRAPH_ACTIVITY_SET",
      pattern_activity_binding: "META_GRAPH",
      cell_activity_binding: "PROJECT_GRAPH",
      pattern_observation: $o.id,
      promotion_rule: "SUPPORT_AT_LEAST_3_OF_4_AND_EXACTLY_ONE_META_ACTIVITY",
      root_readme_readiness: "EXCLUDED",
      executable_ci_generation: "NOT_PERFORMED",
      source_repository_editing: "FORBIDDEN"
    },
    patterns: {
      observed: ($patterns | length),
      support_eligible: ([$patterns[] | select(.support_eligible)] | length),
      meta_bound: ([$patterns[] | select(.meta_bound)] | length),
      promoted: ([$patterns[] | select(.promoted)] | length),
      excluded_without_meta: ([$patterns[] | select(.support_eligible and .meta_activity == null)] | length),
      required: ($p.required_patterns | length),
      missing_required: ($missing_required | length),
      missing_required_ids: $missing_required,
      unknown_required: ($unknown_required | length),
      unknown_required_ids: $unknown_required,
      refuted_required: ($refuted_required | length),
      refuted_required_ids: $refuted_required,
      items: $patterns
    },
    summary: {
      total: $d.target_cells,
      closed: $closed,
      unknown: $unknown,
      refuted: $refuted,
      direct_missing: $direct_missing,
      dependency_blocked: $dependency_blocked,
      meta_activity_nodes: ([$meta.nodes[]? | select(.kind == "Activity")] | length),
      project_activity_nodes: ([$project.nodes[]? | select(.kind == "Activity")] | length),
      expected_output_files: $p.expected_output_files
    },
    proofs: [$d.proof_totals[] as $proof | {
      choice: $proof.proof_choice,
      closed: ([$evaluation.cells[] | select(.proof_choice == $proof.proof_choice and .state == "CLOSED")] | length),
      total: $proof.total
    }],
    metrics: [
      {id: "gooo.metric.generator.activity-bindings.v1", value: $closed, total: $d.target_cells, unit: "cells"},
      {id: "gooo.metric.generator.promoted-patterns.v1", value: ([$patterns[] | select(.promoted)] | length), total: ([$patterns[] | select(.meta_activity != null)] | length), unit: "patterns"},
      {id: "gooo.metric.generator.excluded-without-meta.v1", value: ([$patterns[] | select(.support_eligible and .meta_activity == null)] | length), total: ($patterns | length), unit: "patterns"},
      {id: "gooo.metric.generator.output-files.v1", value: $p.expected_output_files, total: $p.expected_output_files, unit: "files"}
    ],
    cells: $evaluation.cells,
    claim: (if $first_nonclosed != null then
      {id: ($p.id + "/claim/generation"), state: $first_nonclosed.state,
       stage: $first_nonclosed.stage, step: $first_nonclosed.step,
       reason: $first_nonclosed.reason, next_operation: $first_nonclosed.next_operation,
       unknown_class: $first_nonclosed.unknown_class, blocked_by: $first_nonclosed.blocked_by,
       details: []}
    elif ($refuted_required | length) > 0 then
      {id: ($p.id + "/claim/generation"), state: "REFUTED", stage: "PROMOTION",
       step: "REQUIRE_META_BOUND_PATTERN", reason: "REQUIRED_PATTERN_NOT_PROMOTED",
       next_operation: "BIND_PATTERN_TO_GOOO_ACTIVITY_OR_REMOVE_REQUIREMENT",
       unknown_class: null, blocked_by: [], details: $refuted_required}
    elif ($unknown_required | length) > 0 then
      {id: ($p.id + "/claim/generation"), state: "UNKNOWN", stage: "PROMOTION",
       step: "OBSERVE_REQUIRED_PATTERN_ACTIVITY", reason: "REQUIRED_PATTERN_ACTIVITY_UNAVAILABLE",
       next_operation: "PROVIDE_REQUIRED_GOOO_ACTIVITY", unknown_class: "DIRECT_MISSING",
       blocked_by: [], details: $unknown_required}
    else
      {id: ($p.id + "/claim/generation"), state: "CLOSED", stage: null, step: null,
       reason: "EVIDENCE_PROJECT_GENERATED", next_operation: "NONE",
       unknown_class: null, blocked_by: [], details: []}
    end)
  }
' > "$output_real/generation-report.json"

jq -S -n \
  --slurpfile report "$output_real/generation-report.json" \
  --slurpfile project_graph "$project_graph" '
  {
    schema: "gooo/evidence-generator/activity-bindings/v2",
    subject: $report[0].subject,
    binding_authority: $report[0].authority.activity_binding,
    bindings: [$report[0].cells[] as $cell | {
      ordinal: $cell.ordinal,
      cell_id: $cell.id,
      activity: $cell.activity,
      state: $cell.state,
      graph_node_ids: [$project_graph[0].nodes[]? |
        select(.kind == "Activity" and .name == $cell.activity) | .id]
    }]
  }
' > "$output_real/meta/activity-bindings-v2.json"

jq -S -n \
  --slurpfile report "$output_real/generation-report.json" \
  --slurpfile profile "$profile" '
  {
    schema: "gooo/evidence-generator/conformance-plan/v2",
    subject: $report[0].subject,
    executable: false,
    promoted_patterns: [$report[0].patterns.items[] | select(.promoted) |
      {id, support_count, support_total, meta_activity, generator_role}],
    checks: $profile[0].conformance_checks,
    scenarios: $profile[0].scenarios
  }
' > "$output_real/conformance/plan-v2.json"

project_name=$(jq -r '.name' "$profile")
decision=$(jq -r '.decision' "$output_real/generation-report.json")
closed=$(jq -r '.summary.closed' "$output_real/generation-report.json")
unknown=$(jq -r '.summary.unknown' "$output_real/generation-report.json")
refuted=$(jq -r '.summary.refuted' "$output_real/generation-report.json")
promoted=$(jq -r '.patterns.promoted' "$output_real/generation-report.json")
cat > "$output_real/docs/evidence-contract.md" <<EOF
# Generated evidence contract: $project_name

This document was generated from a released Gooo activity graph and has no
independent readiness authority.

- decision: \`$decision\`
- activity cells: \`$closed CLOSED / $unknown UNKNOWN / $refuted REFUTED\`
- promoted meta-bound patterns: \`$promoted\`
- source subject: \`$subject_sha\`
- scenario: \`$scenario\`

The root README is documentation only and is not a readiness predecessor.
The conformance plan is declarative data and must not be executed as code.
EOF

tracked_files=(
  contracts/core-release-lock-v1.json
  contracts/evidence-denominator-v1.json
  meta/activity-bindings-v2.json
  conformance/plan-v2.json
  docs/evidence-contract.md
  generation-report.json
)
entries='[]'
for relative_path in "${tracked_files[@]}"; do
  digest=$(sha256sum "$output_real/$relative_path" | awk '{print $1}')
  size=$(wc -c < "$output_real/$relative_path" | tr -d ' ')
  entries=$(jq -c --arg path "$relative_path" --arg sha256 "$digest" --argjson size "$size" \
    '. + [{path: $path, sha256: $sha256, size_bytes: $size}]' <<<"$entries")
done

jq -S -n \
  --arg subject_sha "$subject_sha" \
  --arg scenario "$scenario" \
  --argjson files "$entries" '
  {
    schema: "gooo/evidence-generator/manifest/v2",
    subject_sha: $subject_sha,
    scenario: $scenario,
    tracked_file_count: ($files | length),
    files: $files
  }
' > "$output_real/generation-manifest.json"
