#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -ne 2 ]; then
  echo "usage: verify.sh BUNDLE REPORT" >&2
  exit 64
fi

bundle=$(realpath "$1")
verification_report=$2
manifest="$bundle/generation-manifest.json"
generation_report="$bundle/generation-report.json"

jq -e '.schema == "gooo/evidence-generator/manifest/v1" and .tracked_file_count == (.files | length)' "$manifest" >/dev/null
jq -e '.schema == "gooo/evidence-generator/report/v1"' "$generation_report" >/dev/null

results='[]'
while IFS=$'\t' read -r relative_path expected_digest expected_size; do
  case "$relative_path" in
    /*|*..*)
      state=REFUTED
      reason=UNSAFE_MANIFEST_PATH
      actual_digest=""
      actual_size=0
      ;;
    *)
      file="$bundle/$relative_path"
      if [ ! -f "$file" ]; then
        state=UNKNOWN
        reason=GENERATED_FILE_UNAVAILABLE
        actual_digest=""
        actual_size=0
      else
        actual_digest=$(sha256sum "$file" | awk '{print $1}')
        actual_size=$(wc -c < "$file" | tr -d ' ')
        if [ "$actual_digest" = "$expected_digest" ] && [ "$actual_size" = "$expected_size" ]; then
          state=CLOSED
          reason=GENERATED_FILE_DIGEST_VERIFIED
        else
          state=REFUTED
          reason=GENERATED_FILE_DIGEST_MISMATCH
        fi
      fi
      ;;
  esac
  item=$(jq -n \
    --arg path "$relative_path" \
    --arg state "$state" \
    --arg reason "$reason" \
    --arg expected_digest "$expected_digest" \
    --arg actual_digest "$actual_digest" \
    --argjson expected_size "$expected_size" \
    --argjson actual_size "$actual_size" \
    '{path:$path,state:$state,reason:$reason,expected_digest:$expected_digest,
      actual_digest:$actual_digest,expected_size_bytes:$expected_size,
      actual_size_bytes:$actual_size}')
  results=$(jq -c --argjson item "$item" '. + [$item]' <<<"$results")
done < <(jq -r '.files[] | [.path,.sha256,.size_bytes] | @tsv' "$manifest")

subject_manifest=$(jq -r '.subject_sha' "$manifest")
subject_report=$(jq -r '.subject.sha' "$generation_report")
if [ "$subject_manifest" = "$subject_report" ]; then identity_match=true; else identity_match=false; fi
actual_output_files=$(find "$bundle" -type f | wc -l | tr -d ' ')

jq -S -n \
  --argjson results "$results" \
  --argjson identity_match "$identity_match" \
  --arg subject_sha "$subject_report" \
  --argjson actual_output_files "$actual_output_files" '
  ([$results[] | select(.state == "CLOSED")] | length) as $closed |
  ([$results[] | select(.state == "UNKNOWN")] | length) as $unknown |
  ([$results[] | select(.state == "REFUTED")] | length) as $refuted |
  ([$results[] | select(.state != "CLOSED")][0] // null) as $first_nonclosed |
  {
    schema: "gooo/evidence-generator/verification/v1",
    decision: (if ($identity_match | not) or $refuted > 0 then "FAIL_CLOSED"
      elif $unknown > 0 then "INCOMPLETE" else "GENERATION_VERIFIED" end),
    subject_sha: $subject_sha,
    manifest_identity_match: $identity_match,
    summary: {
      total: ($results | length),
      closed: $closed,
      unknown: $unknown,
      refuted: $refuted,
      actual_output_files: $actual_output_files
    },
    files: $results,
    claim: (if ($identity_match | not) then
      {state:"REFUTED",stage:"IDENTITY",step:"VERIFY_GENERATION_SUBJECT",
       reason:"GENERATION_SUBJECT_MISMATCH",next_operation:"RESTORE_GENERATION_SUBJECT"}
    elif $first_nonclosed != null then
      {state:$first_nonclosed.state,stage:"DIGEST",step:"VERIFY_GENERATED_FILE_DIGEST",
       reason:$first_nonclosed.reason,next_operation:(if $first_nonclosed.state == "UNKNOWN"
         then "RESTORE_GENERATED_FILE" else "RESTORE_GENERATED_FILE_CONTENT" end)}
    else
      {state:"CLOSED",stage:null,step:null,reason:"ALL_GENERATED_FILE_DIGESTS_VERIFIED",
       next_operation:"NONE"}
    end)
  }
' > "$verification_report"
