#!/usr/bin/env bash
#
# scan.sh
# -------
# A script to:
#   1. Parse a YAML config file using yq
#   2. Clone repositories into stage/<ORG_NAME>/<REPO_NAME>
#   3. Analyze the latest commit and recent tags with govulncheck
#
# Usage:
#   ./scan.sh <config-file>
#
# Requirements:
#   - git
#   - govulncheck
#   - yq
#   - sort with -V flag support (GNU sort)
#   - A POSIX-like shell environment (e.g., bash)

set -euo pipefail
IFS=$'\n\t'

###############################################################################
# Print usage information.
###############################################################################
usage() {
  echo "Usage: $0 <config-file>"
  echo
  echo "Parses the given YAML file for repository URLs using yq,"
  echo "clones each repo into a 'stage' directory,"
  echo "and runs govulncheck on the latest commit and recent tags."
  exit 1
}

###############################################################################
# Validate dependencies are installed
###############################################################################
check_dependencies() {
  local missing_deps=()
  
  for cmd in git yq govulncheck sort; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing_deps+=("$cmd")
    fi
  done
  
  if [[ ${#missing_deps[@]} -gt 0 ]]; then
    echo "Error: Missing required dependencies: ${missing_deps[*]}"
    exit 1
  fi
}

###############################################################################
# Extract repository information from URL
###############################################################################
parse_repo_url() {
  local repo_url="$1"
  local org_name
  local repo_name
  
  org_name=$(echo "$repo_url" | sed -E 's#^https?://[^/]+/([^/]+)/.*#\1#')
  repo_name=$(echo "$repo_url" | sed -E 's#^https?://[^/]+/[^/]+/([^/]+)(\.git)?$#\1#')
  
  echo "org=${org_name};repo=${repo_name}"
}

###############################################################################
# Clone repository if it doesn't exist
###############################################################################
clone_repository() {
  local repo_url="$1"
  local target_dir="$2"
  
  if [[ -d "$target_dir" ]]; then
    echo "Directory '$target_dir' already exists. Updating repository..."
    git -C "$target_dir" fetch --all --tags
  else
    echo "Cloning '$repo_url' into '$target_dir'..."
    git clone --quiet "$repo_url" "$target_dir"
  fi
}

###############################################################################
# Get the latest tags sorted by semver
###############################################################################
get_latest_tags() {
  local repo_dir="$1"
  local num_tags="${2:-3}"
  
  # Get all tags, sort by version (assuming semver), and take the latest n
  git -C "$repo_dir" tag --list | 
    grep -E '^v?[0-9]+\.[0-9]+\.[0-9]+' |
    sort -rV |
    head -n "$num_tags"
}

###############################################################################
# Run govulncheck on a specific git reference
###############################################################################
run_govulncheck() {
  local repo_dir="$1"
  local git_ref="$2"
  local output_dir="$3"
  
  echo "[${output_dir}] Running govulncheck on ${git_ref}..."
  
  # Checkout the specific reference
  git -C "$repo_dir" checkout -q "$git_ref"
  
  # Create output directory for this reference
  mkdir -p "${output_dir}/${git_ref}"

  # Dump the current commit hash
  git -C "$repo_dir" rev-parse HEAD > "${output_dir}/${git_ref}/commit-hash.txt"
  
  # Run govulncheck and save output
  if govulncheck -C "$repo_dir" -show verbose ./... > "${output_dir}/${git_ref}/govulncheck.txt" 2>&1; then
    echo "✓ Completed govulncheck for ${output_dir}/${git_ref}"
  else
    echo "⚠ govulncheck completed with issues for ${output_dir}/${git_ref}"
  fi

  if govulncheck -C "$repo_dir" -format openvex ./... > "${output_dir}/${git_ref}/govulncheck-openvex.json" 2>&1; then
    echo "✓ Completed govulncheck (openvex) for ${output_dir}/${git_ref}"
  else
    echo "⚠ govulncheck (openvex) completed with issues for ${output_dir}/${git_ref}"
  fi
}

###############################################################################
# Process a single repository
###############################################################################
process_repository() {
  local repo_url="$1"
  local repo_info
  local org_name
  local repo_name
  
  # Parse repository information
  repo_info=$(parse_repo_url "$repo_url")
  org_name=$(echo "$repo_info" | cut -d';' -f1 | cut -d'=' -f2)
  repo_name=$(echo "$repo_info" | cut -d';' -f2 | cut -d'=' -f2)
  
  local repo_dir="${STAGE_DIR}/${org_name}/${repo_name}"
  local output_dir="results/${org_name}/${repo_name}"
  
  echo "Processing repository: ${org_name}/${repo_name}"
  
  # Step 1: Clone/update repository
  clone_repository "$repo_url" "$repo_dir"

  # Step 2: Dump govulncheck version
  mkdir -p "$output_dir"
  govulncheck -version > "${output_dir}/govulncheck-version.txt"

  # Step 3: Get refs from config or latest tags
  local refs
  refs=$(yq ".targets[] | select(.repo == \"$repo_url\") | .refs[]" "$config_file" 2>/dev/null || true)
  
  if [[ -z "$refs" ]]; then
    mapfile -t refs < <(get_latest_tags "$repo_dir")
  else
    mapfile -t refs <<< "$refs"
  fi

  # Step 4: Run govulncheck on main branch and refs
  local main_branch
  main_branch=$(git -C "$repo_dir" symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@')
  run_govulncheck "$repo_dir" "$main_branch" "$output_dir"
  
  # Then check each ref
  for ref in "${refs[@]}"; do
    run_govulncheck "$repo_dir" "$ref" "$output_dir"
  done
  
  # Return to main branch/default branch
  git -C "$repo_dir" checkout -q "$main_branch"
  
  echo "Completed analysis of ${org_name}/${repo_name}"
  echo "Results saved in ${output_dir}"
}

###############################################################################
# Main script
###############################################################################
main() {
  local config_file="${1:-}"
  
  if [[ -z "$config_file" ]]; then
    usage
  fi
  
  if [[ ! -f "$config_file" ]]; then
    echo "Error: Configuration file '$config_file' not found."
    exit 1
  fi
  
  # Check for required dependencies
  check_dependencies
  
  # Create stage directory
  STAGE_DIR="stage"
  mkdir -p "$STAGE_DIR"
  
  # Use yq to extract repository URLs and process each one
  declare -a pids
  while IFS= read -r repo_url; do
    echo "Processing repository: $repo_url"
    process_repository "$repo_url" &
    pids+=($!)
  done < <(yq '.targets[] | .repo' "$config_file")

  # Wait for all background processes to complete and check their exit status
  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      echo "Error: A subprocess failed."
      exit 1
    fi
  done
  
  echo "All repositories processed successfully!"
}

# Execute main function
main "$@"