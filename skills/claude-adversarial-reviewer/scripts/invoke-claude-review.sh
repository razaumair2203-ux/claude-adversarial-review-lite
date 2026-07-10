#!/usr/bin/env bash
set -euo pipefail

BUNDLE_PATH=${1:-}
RESULT_PATH=${2:-}
MODEL=${3:-}
MAX_TURNS=${CLAUDE_REVIEW_MAX_TURNS:-8}
MAX_BUDGET_USD=${CLAUDE_REVIEW_MAX_BUDGET_USD:-3.00}
TIMEOUT_SECONDS=${CLAUDE_REVIEW_TIMEOUT_SECONDS:-600}
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKILL_DIR=$(cd -- "$SCRIPT_DIR/.." && pwd)
SCHEMA_PATH="$SKILL_DIR/references/review-schema.json"
PROMPT_PATH="$SKILL_DIR/references/reviewer-prompt.md"

write_error() {
  local result=$1 quality=$2 message=$3
  mkdir -p -- "$(dirname -- "$RESULT_PATH")"
  if command -v jq >/dev/null 2>&1; then
    jq -n --arg result "$result" --arg quality "$quality" --arg errors "$message" \
      '{result:$result,verdict:null,review_quality:$quality,review:null,errors:$errors,session_id:null}' > "$RESULT_PATH"
  else
    printf '{"result":"setup_needed","verdict":null,"review_quality":"degraded_environmental","review":null,"errors":"jq is required by the POSIX runner.","session_id":null}\n' > "$RESULT_PATH"
  fi
}

if [[ -z "$BUNDLE_PATH" || -z "$RESULT_PATH" || ! -s "$BUNDLE_PATH" ]]; then
  [[ -n "$RESULT_PATH" ]] && write_error invalid_output unknown "Bundle is missing or empty."
  exit 2
fi
BUNDLE_PATH=$(cd -- "$(dirname -- "$BUNDLE_PATH")" && pwd)/$(basename -- "$BUNDLE_PATH")
result_dir=$(dirname -- "$RESULT_PATH")
mkdir -p -- "$result_dir"
RESULT_PATH=$(cd -- "$result_dir" && pwd)/$(basename -- "$RESULT_PATH")
resolve_claude_bin() {
  for candidate in "${CLAUDE_REVIEW_CLI:-}" "${CLAUDE_BIN:-}" claude "$HOME/.local/bin/claude" "$HOME/.npm-global/bin/claude"; do
    [[ -n "$candidate" ]] || continue
    if [[ -x "$candidate" ]]; then printf '%s\n' "$candidate"; return 0; fi
    if command -v "$candidate" >/dev/null 2>&1; then command -v "$candidate"; return 0; fi
  done
  return 1
}

CLAUDE_COMMAND=$(resolve_claude_bin || true)
if [[ ! -s "$SCHEMA_PATH" || ! -s "$PROMPT_PATH" || -z "$CLAUDE_COMMAND" ]]; then
  write_error setup_needed degraded_environmental "Claude CLI or required skill resources are unavailable."
  exit 2
fi
command -v jq >/dev/null 2>&1 || { write_error setup_needed degraded_environmental "jq is required by the POSIX runner."; exit 2; }

stdout=$(mktemp)
stderr=$(mktemp)
review_cwd=$(mktemp -d)
trap 'rm -f -- "$stdout" "$stderr"; rm -rf -- "$review_cwd"' EXIT
args=(-p --permission-mode dontAsk --tools "" --disable-slash-commands --setting-sources "" --strict-mcp-config --mcp-config '{"mcpServers":{}}' --settings '{"disableAllHooks":true,"autoMemoryEnabled":false}' --output-format json --json-schema "$(<"$SCHEMA_PATH")" --system-prompt-file "$PROMPT_PATH" --max-turns "$MAX_TURNS" --max-budget-usd "$MAX_BUDGET_USD" --no-session-persistence)
[[ -n "$MODEL" ]] && args+=(--model "$MODEL")
set +e
(cd -- "$review_cwd" && timeout "$TIMEOUT_SECONDS" "$CLAUDE_COMMAND" "${args[@]}" < "$BUNDLE_PATH" > "$stdout" 2> "$stderr")
code=$?
set -e
if [[ $code -ne 0 ]]; then
  diagnostic=$(head -c 1000 "$stderr")
  [[ -n "$diagnostic" ]] || diagnostic=$(head -c 1000 "$stdout")
  [[ $code -eq 124 ]] && write_error timeout degraded_environmental "Claude review timed out." || write_error launch_failure degraded_environmental "Claude exited with code $code. $diagnostic"
  exit 3
fi
if ! jq -e '(.structured_output // (.result | fromjson?)) as $r | $r.verdict and $r.review_quality and ($r.findings | type == "array")' "$stdout" >/dev/null 2>&1; then
  write_error invalid_output unknown "Claude returned malformed or incomplete structured output."
  exit 4
fi
verdict=$(jq -r '(.structured_output // (.result | fromjson?)).verdict' "$stdout")
count=$(jq '(.structured_output // (.result | fromjson?)).findings | length' "$stdout")
if [[ ( "$verdict" == approved && "$count" -ne 0 ) || ( "$verdict" == revise && "$count" -eq 0 ) ]]; then
  write_error invalid_output unknown "Verdict and finding count are inconsistent."
  exit 4
fi
mkdir -p -- "$(dirname -- "$RESULT_PATH")"
jq '(.structured_output // (.result | fromjson?)) as $r | {result:"success", verdict:$r.verdict, review_quality:$r.review_quality, review:$r, errors:null, session_id:(.session_id // null)}' "$stdout" > "$RESULT_PATH"
