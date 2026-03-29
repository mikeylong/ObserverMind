#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

# Exclude the scanner implementation itself so detection patterns do not self-trigger.
excluded_files=(
  ".github/workflows/privacy-scan.yml"
  "scripts/privacy_scan.sh"
)

findings=0

is_excluded() {
  local path="$1"
  local excluded
  for excluded in "${excluded_files[@]}"; do
    if [[ "$path" == "$excluded" ]]; then
      return 0
    fi
  done
  return 1
}

emit_finding() {
  local file="$1"
  local line="$2"
  local label="$3"
  local text="$4"

  findings=$((findings + 1))
  printf 'privacy-scan: %s in %s:%s\n' "$label" "$file" "$line" >&2
  printf '  %s\n' "$text" >&2

  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    printf '::error file=%s,line=%s,title=Privacy scan::%s: %s\n' "$file" "$line" "$label" "$text"
  fi
}

scan_content_pattern() {
  local label="$1"
  local pattern="$2"
  local file matches match line text

  while IFS= read -r file; do
    is_excluded "$file" && continue
    [[ -f "$file" ]] || continue

    if [[ -s "$file" ]] && ! LC_ALL=C grep -Iq . "$file"; then
      continue
    fi

    matches="$(LC_ALL=C grep -nE -e "$pattern" "$file" || true)"
    [[ -n "$matches" ]] || continue

    while IFS= read -r match; do
      [[ -n "$match" ]] || continue
      line="${match%%:*}"
      text="${match#*:}"
      emit_finding "$file" "$line" "$label" "$text"
    done <<< "$matches"
  done < <(git ls-files)
}

scan_file_name_pattern() {
  local label="$1"
  local pattern="$2"
  local file

  while IFS= read -r file; do
    is_excluded "$file" && continue
    if [[ "$file" =~ $pattern ]]; then
      emit_finding "$file" "1" "$label" "tracked filename matches a sensitive-file pattern"
    fi
  done < <(git ls-files)
}

scan_content_pattern "Private key" '-----BEGIN (RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----|-----BEGIN PGP PRIVATE KEY BLOCK-----'
scan_content_pattern "GitHub token" 'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}'
scan_content_pattern "AWS access key" 'AKIA[0-9A-Z]{16}'
scan_content_pattern "Google API key" 'AIza[0-9A-Za-z_-]{35}'
scan_content_pattern "Slack token" 'xox[baprs]-[A-Za-z0-9-]{10,}'
scan_content_pattern "Machine-specific path" '/Users/[^/]+/|/home/[^/]+/'

scan_file_name_pattern "Sensitive filename" '(^|/)\.env(\..+)?$|(^|/)\.netrc$|(^|/)id_(rsa|ed25519)$|\.pem$|\.p12$|\.pfx$|\.key$'

if [[ "$findings" -gt 0 ]]; then
  printf 'privacy-scan: failed with %d finding(s)\n' "$findings" >&2
  exit 1
fi

printf 'privacy-scan: passed, no obvious public-repo blockers found in tracked files.\n'
