#!/usr/bin/env sh
# PostToolUse hook for MANIFEST/MonkScript edits.
# Asks local monk-agent for analyzer diagnostics and feeds concise results back
# into Claude Code after template edits. The hook is intentionally best-effort:
# missing monk-agent, auth issues, or unavailable analyzer support should not
# block the user's edit.

set -eu

input="$(cat)"

tool_name="$(printf '%s' "$input" | jq -r '.tool_name // ""' 2>/dev/null || true)"
case "$tool_name" in
  Edit|Write|MultiEdit) ;;
  *) exit 0 ;;
esac

file_path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // ""' 2>/dev/null || true)"
[ -n "$file_path" ] || exit 0

case "$file_path" in
  */MANIFEST|MANIFEST|*.yaml|*.yml) ;;
  *) exit 0 ;;
esac

if [ ! -f "$file_path" ]; then
  # Deleted or virtual files do not need immediate template diagnostics.
  exit 0
fi

dirname_of() {
  dirname "$1" 2>/dev/null || printf '.\n'
}

find_workspace_root() {
  start="$1"
  dir="$start"
  while [ "$dir" != "/" ] && [ -n "$dir" ]; do
    if [ -f "$dir/MANIFEST" ]; then
      printf '%s\n' "$dir"
      return
    fi
    dir="$(dirname_of "$dir")"
  done

  if [ -n "${CLAUDE_PROJECT_DIR:-}" ] && [ -d "$CLAUDE_PROJECT_DIR" ]; then
    printf '%s\n' "$CLAUDE_PROJECT_DIR"
    return
  fi

  pwd
}

workspace_root="$(find_workspace_root "$(dirname_of "$file_path")")"
manifest_path="$workspace_root/MANIFEST"
[ -f "$manifest_path" ] || exit 0

case "$file_path" in
  "$workspace_root"/*) rel_path="${file_path#"$workspace_root"/}" ;;
  *) rel_path="$file_path" ;;
esac

is_manifest=0
[ "$(basename "$file_path")" = "MANIFEST" ] && is_manifest=1

if [ "$is_manifest" -ne 1 ]; then
  # Avoid running the analyzer for ordinary YAML files in app repos. Trigger
  # when the file is loaded by MANIFEST or contains common Monk YAML markers.
  if ! awk '
    BEGIN { found = 0 }
    /^[[:space:]]*#/ { next }
    toupper($1) == "LOAD" {
      for (i = 2; i <= NF; i++) {
        if ($i == rel || $i == base) found = 1
      }
    }
    END { exit(found ? 0 : 1) }
  ' rel="$rel_path" base="$(basename "$file_path")" "$manifest_path" &&
    ! grep -Eq '^[[:space:]]*(defines|inherits|containers|services|variables|connections|depends|ingress-routes):|<-' "$file_path"
  then
    exit 0
  fi
fi

if ! command -v curl >/dev/null 2>&1; then
  exit 0
fi

host="${MONK_AGENT_HOST:-127.0.0.1}"
port="${MONK_AGENT_PORT:-7419}"
mcp_url="http://$host:$port/mcp"

payload="$(
  jq -n --arg workspaceRoot "$workspace_root" '{
    jsonrpc: "2.0",
    id: "monk-diagnostics-hook",
    method: "tools/call",
    params: {
      name: "monk.analyzer.diagnose",
      arguments: {
        workspaceRoot: $workspaceRoot
      }
    }
  }'
)"

response="$(
  curl -fsS \
    --max-time "${MONK_AGENT_HOOK_TIMEOUT:-8}" \
    -H "content-type: application/json" \
    --data "$payload" \
    "$mcp_url" 2>/dev/null
)" || exit 0

diagnostics_json="$(
  printf '%s' "$response" |
    jq -r '.result.content[0].text // empty' 2>/dev/null
)" || exit 0

[ -n "$diagnostics_json" ] || exit 0

available="$(printf '%s' "$diagnostics_json" | jq -r '.available // false' 2>/dev/null || printf 'false')"
[ "$available" = "true" ] || exit 0

issue_count="$(printf '%s' "$diagnostics_json" | jq '[.diagnostics[]? | select(.severity == "error" or .severity == "warning")] | length' 2>/dev/null || printf '0')"
[ "$issue_count" -gt 0 ] 2>/dev/null || exit 0

output="$(
  printf '%s' "$diagnostics_json" |
    jq -r '
      def loc:
        (.file // .uri // "unknown") +
        (if (.line // .startLine) then ":" + ((.line // .startLine) | tostring) else "" end);

      [.diagnostics[]? | select(.severity == "error")] as $errors |
      [.diagnostics[]? | select(.severity == "warning")] as $warnings |
      "Diagnostics: \($errors | length) error(s), \($warnings | length) warning(s)" +
      (if ($errors | length) > 0 then
        "\n\n## Errors (must fix):\n" +
        ($errors[:20] | map("- [\(.code // "error")] \(loc): \(.message)") | join("\n"))
      else "" end) +
      (if ($warnings | length) > 0 then
        "\n\n## Warnings (should fix):\n" +
        ($warnings[:10] | map("- [\(.code // "warning")] \(loc): \(.message)") | join("\n"))
      else "" end)
    ' 2>/dev/null
)" || exit 0

[ -n "$output" ] || exit 0

message="Monk analyzer diagnostics after editing $rel_path:

$output

Use the monk-editor workflow to fix any errors before deploying."

jq -n --arg message "$message" '{
  systemMessage: $message
}'
