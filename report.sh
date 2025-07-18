#!/usr/bin/env bash

set -euo pipefail
IFS=$'\n\t'

# Function to generate the report for a single JSON file
generate_report_for_json() {
  local json_file="$1"
  local module_name="$2"
  local git_ref="$3"

  local impacted_entries
  impacted_entries=$(jq -r '.statements? // [] | map(select(.status == "affected")) | .[] | "| \(.vulnerability.name) | \(.vulnerability["@id"]) | \(.status) | \(.impact_statement // "N/A") |"' "$json_file" 2>&1) || {
    echo "Warning: Skipping invalid JSON file: $json_file" >&2
    echo "jq error output: $impacted_entries" >&2
    echo "JSON file content:" >&2
    cat "$json_file" >&2
    echo >&2
    echo "### ⚠️ ${git_ref} (Skipped - Invalid JSON)"
    echo
    echo "Unable to process JSON file: \`$json_file\`"
    echo
    echo "Reports: [${module_name}/${git_ref}](results/${module_name}/${git_ref})"
    echo
    return 0
  }

  if [[ -n "$impacted_entries" ]]; then
    echo "### ⚠️ ${git_ref}"
    echo
    echo "Active affected vulnerabilities:"
    echo
    echo "| name | @id | status | impact statement |"
    echo "|------|-----|--------|------------------|"
    echo "$impacted_entries"
    echo
  else
    echo "### ✅ ${git_ref}"
    echo
    echo "No active affected vulnerabilities found in ${git_ref}"
    echo
  fi

  echo "Reports: [${module_name}/${git_ref}](results/${module_name}/${git_ref})"
  echo
}

# Main function to generate the report
generate_report() {
  local output_file="report.md"

  echo "# OpenVEX Report" > "$output_file"
  echo >> "$output_file"
  echo "Last updated time: $(date)" >> "$output_file"
  echo >> "$output_file"

  for module_dir in results/*/*; do
    # trim the "results/" prefix
    module_name="${module_dir#results/}"
    echo "## ${module_name}" >> "$output_file"
    echo >> "$output_file"

    for json_file in "$module_dir"/*/govulncheck-openvex.json; do
      git_ref=$(basename "$(dirname "$json_file")")
      generate_report_for_json "$json_file" "$module_name" "$git_ref" >> "$output_file"
    done
  done
}

# Execute the main function
generate_report