#!/usr/bin/env bash
set -euo pipefail
repo=${1:?repo root required}
output=${2:?output path required}
mkdir -p -- "$(dirname -- "$output")"
{
  echo status
  git -C "$repo" status --porcelain=v1 --untracked-files=all | LC_ALL=C sort
  echo dirty-tracked-sha256
  { git -c core.quotePath=false -C "$repo" diff --name-only --diff-filter=ACMRTUXB -z; git -c core.quotePath=false -C "$repo" diff --cached --name-only --diff-filter=ACMRTUXB -z; } |
    while IFS= read -r -d '' path; do
      [[ -f "$repo/$path" ]] || continue
      if command -v sha256sum >/dev/null 2>&1; then sha256sum "$repo/$path" | sed "s#  $repo/#  #"
      else shasum -a 256 "$repo/$path" | sed "s#  $repo/#  #"; fi
    done
  echo untracked-sha256
  git -C "$repo" ls-files --others --exclude-standard -z |
    while IFS= read -r -d '' path; do
      [[ -f "$repo/$path" ]] || continue
      if command -v sha256sum >/dev/null 2>&1; then sha256sum "$repo/$path" | sed "s#  $repo/#  #"
      else shasum -a 256 "$repo/$path" | sed "s#  $repo/#  #"; fi
    done
} > "$output"
