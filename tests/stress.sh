#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
runner="$root/skills/claude-adversarial-reviewer/scripts/invoke-claude-review.sh"
tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT
chmod +x "$root/tests/mock/claude-output" "$root/tests/mock/claude-sleep" "$root/tests/mock/claude-error" 2>/dev/null || true
bundle="$tmp/bundle.md"
printf '# Synthetic bundle\nNo repository content.\n' > "$bundle"
export CLAUDE_BIN="$root/tests/mock/claude-output"
export MOCK_CLAUDE_EXIT=0

export MOCK_CLAUDE_OUTPUT="$root/tests/fixtures/approved.json"
bash "$runner" "$bundle" "$tmp/approved.json"
jq -e '.result == "success" and .verdict == "approved"' "$tmp/approved.json" >/dev/null
echo "PASS approved"

export MOCK_CLAUDE_OUTPUT="$root/tests/fixtures/approved-result-string.json"
bash "$runner" "$bundle" "$tmp/approved-result-string.json"
jq -e '.result == "success" and .verdict == "approved"' "$tmp/approved-result-string.json" >/dev/null
echo "PASS approved-result-string"

export MOCK_CLAUDE_OUTPUT="$root/tests/fixtures/revise.json"
bash "$runner" "$bundle" "$tmp/revise.json"
jq -e '.result == "success" and .verdict == "revise"' "$tmp/revise.json" >/dev/null
echo "PASS revise"

export MOCK_CLAUDE_OUTPUT="$root/tests/fixtures/inconsistent.json"
set +e
bash "$runner" "$bundle" "$tmp/inconsistent.json"
code=$?
set -e
[[ $code -eq 4 ]]
jq -e '.result == "invalid_output"' "$tmp/inconsistent.json" >/dev/null
echo "PASS inconsistent"

export CLAUDE_BIN="$root/tests/mock/claude-sleep"
export CLAUDE_REVIEW_TIMEOUT_SECONDS=1
set +e
bash "$runner" "$bundle" "$tmp/timeout.json"
code=$?
set -e
[[ $code -eq 3 ]]
jq -e '.result == "timeout"' "$tmp/timeout.json" >/dev/null
echo "PASS timeout"

export CLAUDE_BIN="$root/tests/mock/claude-error"
unset CLAUDE_REVIEW_TIMEOUT_SECONDS
set +e
bash "$runner" "$bundle" "$tmp/error.json"
code=$?
set -e
[[ $code -eq 3 ]]
jq -e '.result == "launch_failure" and (.errors | contains("C:\\temp\\q"))' "$tmp/error.json" >/dev/null
echo "PASS escaped-error"
echo "POSIX stress suite passed: 6/6"
