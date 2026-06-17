#!/usr/bin/env sh
# PostToolUse hook for MANIFEST/MonkScript edits.
# Runs monk-agent analyzer diagnostics after file edits and logs results to
# stderr. Antigravity PostToolUse output must be an empty JSON object — results
# cannot be injected back into the conversation from this event type.
#
# Antigravity PostToolUse I/O:
#   stdin:  {"stepIdx":N,"transcriptPath":"...","workspacePaths":[...],...}
#   stdout: {}

set -eu

# Antigravity requires PostToolUse stdout to be {}
trap 'printf "%s\n" "{}"' EXIT

input="$(cat)"

transcript="$(printf '%s' "$input" | jq -r '.transcriptPath // ""' 2>/dev/null || true)"
step_idx="$(printf '%s' "$input" | jq -r '.stepIdx // 0' 2>/dev/null || printf '0')"

[ -n "$transcript" ] || exit 0
[ -f "$transcript" ] || exit 0

# Extract the edited file path from the transcript at stepIdx.
# write_to_file and replace_file_content both use TargetFile.
file_path="$(jq -rs --argjson i "$step_idx" '
  (.[$i] // {}) |
  .toolCall.args.TargetFile // .toolCall.args.target_file // ""
' "$transcript" 2>/dev/null || true)"

[ -n "$file_path" ] || exit 0

case "$file_path" in
  */MANIFEST|MANIFEST|*.yaml|*.yml) ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

dirname_of() { dirname "$1" 2>/dev/null || printf '.\n'; }

find_workspace_root() {
  dir="$(dirname_of "$1")"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    [ -f "$dir/MANIFEST" ] && { printf '%s\n' "$dir"; return; }
    dir="$(dirname_of "$dir")"
  done
  printf '%s' "$input" | jq -r '.workspacePaths[0] // ""' 2>/dev/null || pwd
}

workspace_root="$(find_workspace_root "$file_path")"
[ -f "$workspace_root/MANIFEST" ] || exit 0

command -v curl >/dev/null 2>&1 || exit 0

host="${MONK_AGENT_HOST:-127.0.0.1}"
port="${MONK_AGENT_PORT:-7419}"

payload="$(jq -n --arg workspaceRoot "$workspace_root" '{
  jsonrpc: "2.0",
  id: "monk-diagnostics-hook",
  method: "tools/call",
  params: {
    name: "monk.analyzer.diagnose",
    arguments: { workspaceRoot: $workspaceRoot }
  }
}')"

response="$(curl -fsS \
  --max-time "${MONK_AGENT_HOOK_TIMEOUT:-8}" \
  -H "content-type: application/json" \
  --data "$payload" \
  "http://$host:$port/mcp" 2>/dev/null)" || exit 0

diagnostics_json="$(printf '%s' "$response" | jq -r '.result.content[0].text // empty' 2>/dev/null)" || exit 0
[ -n "$diagnostics_json" ] || exit 0

available="$(printf '%s' "$diagnostics_json" | jq -r '.available // false' 2>/dev/null || printf 'false')"
[ "$available" = "true" ] || exit 0

issue_count="$(printf '%s' "$diagnostics_json" | \
  jq '[.diagnostics[]? | select(.severity == "error" or .severity == "warning")] | length' \
  2>/dev/null || printf '0')"
[ "$issue_count" -gt 0 ] 2>/dev/null || exit 0

# Log to stderr — stdout must stay as {} (see trap above)
printf '%s' "$diagnostics_json" | jq -r '
  [.diagnostics[]? | select(.severity == "error" or .severity == "warning")] |
  "monk-diagnostics: \(length) issue(s)\n" +
  (map("  [\(.severity)] \(.file // "?")\(if .line then ":" + (.line|tostring) else "" end): \(.message)") | join("\n"))
' >&2 2>/dev/null || true
