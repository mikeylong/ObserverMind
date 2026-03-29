#!/usr/bin/env bash
set -euo pipefail

latest_tag="$(git tag --list 'v*' --sort=-version:refname | head -n 1)"

if [[ -z "${latest_tag}" ]]; then
  printf 'v0.1.0\n'
  exit 0
fi

if [[ ! "${latest_tag}" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  printf 'Latest tag is not semver: %s\n' "${latest_tag}" >&2
  exit 1
fi

major="${BASH_REMATCH[1]}"
minor="${BASH_REMATCH[2]}"
patch="${BASH_REMATCH[3]}"

printf 'v%s.%s.%s\n' "${major}" "${minor}" "$((patch + 1))"
