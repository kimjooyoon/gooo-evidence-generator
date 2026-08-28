#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 7 ]; then
  echo "usage: bind-activity-resolutions.sh GOOO SOURCE GRAPH SELECTORS CORE_LOCK OUTPUT ROLE" >&2
  exit 64
fi

gooo=$1
source_file=$2
graph=$3
selectors=$4
core_lock=$5
output=$6
role=$7

test -x "$gooo"
test -f "$source_file"
test -f "$graph"
test -f "$selectors"
test -f "$core_lock"

jq -e --arg role "$role" '
  .schema=="gooo/evidence-generator/activity-selector-set/v1" and
  .role==$role and (.selectors|length)>0 and
  ([.selectors[].ordinal]==[range(1;(.selectors|length)+1)]) and
  ([.selectors[].id]|unique|length)==(.selectors|length) and
  ([.selectors[].activity]|unique|length)==(.selectors|length)
' "$selectors" >/dev/null
jq -e '.schema_version=="gooo-graph/v1" and .ir.status=="available"' "$graph" >/dev/null
jq -e '
  .schema=="gooo/core-release-lock/v1" and .tag=="v0.2.0-dev" and
  .schemas.activity_cardinality_resolution=="gooo/activity-cardinality-resolution/v1" and
  (.assets|length)==1 and .assets[0].name=="gooo-linux-amd64.tar.gz" and
  (.assets[0].sha256|test("^[0-9a-f]{64}$"))
' "$core_lock" >/dev/null

work=$(mktemp -d)
trap 'rm -r "$work"' EXIT
mkdir -p "$work/entries"

while IFS=$'\t' read -r ordinal id activity; do
  printf -v receipt '%s/receipt-%04d.json' "$work" "$ordinal"
  if "$gooo" graph resolve-activity "$source_file" --name "$activity" > "$receipt"; then
    status=0
  else
    status=$?
  fi
  jq -e --arg activity "$activity" --arg source_file "$source_file" --slurpfile graph "$graph" '
    .schema=="gooo/activity-cardinality-resolution/v1" and
    .selector.name==$activity and .subject.source_file==$source_file and
    .subject.source_digest==$graph[0].source_digest and
    .subject.semantic_digest==$graph[0].ir.semantic_digest and
    ((.decision=="CLOSED" and .claim.state=="CLOSED" and .occurrences==1 and (.matches|length)==1 and
      .claim.stage=="RESOLUTION" and .claim.step=="RESOLVE_ACTIVITY_CARDINALITY" and
      .claim.reason=="ACTIVITY_UNIQUELY_RESOLVED" and .claim.next_operation=="USE_RESOLVED_ACTIVITY" and
      .claim.proof_choice=="COHERENCE") or
     (.decision=="UNKNOWN" and .claim.state=="UNKNOWN" and .occurrences==0 and (.matches|length)==0 and
      .claim.stage=="RESOLUTION" and .claim.step=="RESOLVE_ACTIVITY_CARDINALITY" and
      .claim.reason=="ACTIVITY_NOT_FOUND" and .claim.unknown_class=="DIRECT_MISSING" and
      .claim.next_operation=="DECLARE_OR_WIDEN_ACTIVITY_SELECTOR" and .claim.proof_choice=="FOUNDATION") or
     (.decision=="REFUTED" and .claim.state=="REFUTED" and .occurrences>1 and (.matches|length)==.occurrences and
      .claim.stage=="RESOLUTION" and .claim.step=="RESOLVE_ACTIVITY_CARDINALITY" and
      .claim.reason=="AMBIGUOUS_ACTIVITY_BINDING" and .claim.next_operation=="NARROW_ACTIVITY_SELECTOR" and
      .claim.proof_choice=="REGRESSION"))
  ' "$receipt" >/dev/null
  decision=$(jq -r '.decision' "$receipt")
  if [ "$decision" = "CLOSED" ]; then test "$status" -eq 0; else test "$status" -ne 0; fi
  jq -S -n --argjson ordinal "$ordinal" --arg id "$id" --arg activity "$activity" \
    --slurpfile receipt "$receipt" \
    '{ordinal:$ordinal,id:$id,activity:$activity,receipt:$receipt[0]}' \
    > "$work/entries/$(printf '%04d' "$ordinal").json"
done < <(jq -r '.selectors[]|[.ordinal,.id,.activity]|@tsv' "$selectors")

jq -S -s '.' "$work"/entries/*.json > "$work/entries.json"
selector_digest=$(sha256sum "$selectors" | awk '{print $1}')
jq -S -n \
  --arg role "$role" \
  --arg source_file "$source_file" \
  --arg selector_set_sha256 "$selector_digest" \
  --slurpfile graph "$graph" \
  --slurpfile lock "$core_lock" \
  --slurpfile entries "$work/entries.json" '
  ($entries[0]) as $items |
  {
    schema:"gooo/evidence-generator/activity-resolution-observation/v1",
    role:$role,
    core_release:{repository:$lock[0].repository,tag:$lock[0].tag,tag_object_sha:$lock[0].tag_object_sha,target_commit_sha:$lock[0].target_commit_sha,binary_asset:$lock[0].assets[0].name,binary_sha256:$lock[0].assets[0].sha256,resolution_schema:$lock[0].schemas.activity_cardinality_resolution},
    source:{file:$source_file,source_digest:$graph[0].source_digest,semantic_digest:$graph[0].ir.semantic_digest},
    selector_set_sha256:$selector_set_sha256,
    summary:{expected:($items|length),observed:($items|length),closed:([$items[]|select(.receipt.decision=="CLOSED")]|length),unknown:([$items[]|select(.receipt.decision=="UNKNOWN")]|length),refuted:([$items[]|select(.receipt.decision=="REFUTED")]|length),unique_selectors:([$items[].activity]|unique|length)},
    entries:$items
  }
' > "$work/observation.json"

jq -S --slurpfile observation "$work/observation.json" \
  '. + {activity_resolution_observation:$observation[0]}' "$graph" > "$output"
