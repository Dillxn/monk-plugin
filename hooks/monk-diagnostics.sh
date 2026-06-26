#!/usr/bin/env sh
# PostToolUse hook for MANIFEST/MonkScript edits.
# Asks local monk-agent for analyzer diagnostics and feeds concise results back
# into Claude Code after template edits.
#
# All logic (path resolution, workspace discovery, the MCP call, and formatting)
# lives in `monk-agent hook diagnostics`, so this wrapper depends only on the
# binary the plugin already installs — no jq/curl/awk. The hook is best-effort:
# a missing binary, missing agent, auth issues, or unavailable analyzer support
# must never block the user's edit, so we always exit 0.

set -eu

agent="${MONK_AGENT_PATH:-${MONK_AGENT_INSTALL_DIR:-"$HOME/.monk/bin"}/monk-agent}"
[ -x "$agent" ] || exit 0

cat | "$agent" hook diagnostics --format claude || exit 0

exit 0
