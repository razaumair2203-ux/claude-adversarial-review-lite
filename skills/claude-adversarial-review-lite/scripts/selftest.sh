#!/usr/bin/env bash
set -euo pipefail

LIVE_PROBE=0
[[ "${1:-}" == "--live-probe" ]] && LIVE_PROBE=1

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
REPO_ROOT=$(cd -- "$SKILL_DIR/../.." && pwd)
RUNNER="$SCRIPT_DIR/invoke-claude-review.sh"

resolve_claude_bin() {
  for candidate in "${CLAUDE_REVIEW_CLI:-}" "${CLAUDE_BIN:-}" claude "$HOME/.local/bin/claude" "$HOME/.npm-global/bin/claude"; do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return 0; fi
  done
  return 1
}

status=0
report='[]'
add_check() {
  local name=$1 state=$2 detail=$3
  [[ "$state" == pass ]] || status=2
  if command -v jq >/dev/null 2>&1; then
    report=$(jq -c --arg name "$name" --arg status "$state" --arg detail "$detail" '. + [{name:$name,status:$status,detail:$detail}]' <<<"$report")
  else
    printf '%s\t%s\t%s\n' "$state" "$name" "$detail"
  fi
}

if command -v git >/dev/null 2>&1; then add_check git pass "$(git --version)"; else add_check git fail "Git is not available."; fi
if command -v jq >/dev/null 2>&1; then add_check jq pass "$(jq --version)"; else add_check jq fail "jq is required."; fi
if command -v timeout >/dev/null 2>&1; then add_check timeout pass "available"; else add_check timeout fail "timeout is required."; fi

claude_bin=$(resolve_claude_bin || true)
if [[ -n "$claude_bin" ]]; then
  add_check claude_cli pass "$claude_bin"
  add_check claude_version pass "$("$claude_bin" --version 2>&1 || true)"
  auth=$("$claude_bin" auth status 2>&1 || true)
  if grep -q '"loggedIn"[[:space:]]*:[[:space:]]*true' <<<"$auth"; then add_check claude_auth pass "loggedIn=true"; else add_check claude_auth fail "$auth"; fi
else
  add_check claude_cli fail "Set CLAUDE_REVIEW_CLI/CLAUDE_BIN or install/authenticate Claude Code CLI."
fi

temp_dir=$(mktemp -d)
trap 'rm -rf -- "$temp_dir"' EXIT
printf ok > "$temp_dir/write-probe.txt"
add_check temp_write pass "$temp_dir"

if bash "$REPO_ROOT/tests/stress.sh" >/dev/null; then add_check mock_stress pass "POSIX stress suite"; else add_check mock_stress fail "POSIX stress suite failed"; fi

if [[ "$LIVE_PROBE" -eq 1 && -n "$claude_bin" ]]; then
  bundle="$temp_dir/synthetic-bundle.md"
  result="$temp_dir/synthetic-result.json"
  printf '# Synthetic self-test bundle\n\nNo repository content is included.\n' > "$bundle"
  export CLAUDE_REVIEW_CLI="$claude_bin"
  if CLAUDE_REVIEW_MAX_TURNS=2 CLAUDE_REVIEW_TIMEOUT_SECONDS=120 bash "$RUNNER" "$bundle" "$result" >/dev/null; then
    add_check live_probe pass "$(jq -r '.result' "$result")"
  else
    add_check live_probe fail "$(cat "$result" 2>/dev/null || true)"
  fi
fi

if command -v jq >/dev/null 2>&1; then
  jq -n --arg result "$([[ "$status" -eq 0 ]] && printf pass || printf fail)" --argjson checks "$report" '{result:$result,checks:$checks}'
fi
exit "$status"
