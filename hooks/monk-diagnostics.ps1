# PostToolUse hook for MANIFEST/MonkScript edits.
# Asks local monk-agent for analyzer diagnostics and feeds concise results back
# into Claude Code after template edits.
#
# All logic (path resolution, workspace discovery, the MCP call, and formatting)
# lives in `monk-agent hook diagnostics`, so this wrapper depends only on the
# binary the plugin already installs. Best-effort: a missing binary, missing
# agent, auth issues, or unavailable analyzer support must never block the
# user's edit, so we always exit 0.

$hookInput = [Console]::In.ReadToEnd()

# If bash is available the .sh sibling hook handles this; bow out to avoid
# emitting the same diagnostics twice (PostToolUse runs every hook in the list).
if (Get-Command bash -ErrorAction SilentlyContinue) { exit 0 }

$agentDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $agentDir "monk-agent.exe" }

if (-not (Test-Path $agent)) { exit 0 }

try { $hookInput | & $agent hook diagnostics --format claude } catch { }
exit 0
