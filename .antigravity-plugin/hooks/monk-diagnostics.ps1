# PostToolUse hook for MANIFEST/MonkScript edits.
# Windows (stock, no Git Bash) counterpart of monk-diagnostics.sh.
#
# All logic (path resolution, workspace discovery, the MCP call, and formatting)
# lives in `monk-agent hook diagnostics`, so this wrapper depends only on the
# binary the plugin already installs. Best-effort: a missing binary, missing
# agent, auth issues, or unavailable analyzer support must never block the
# user's edit, so we always exit 0.

$ErrorActionPreference = "SilentlyContinue"

$hookInput = [Console]::In.ReadToEnd()

# If bash is available the .sh sibling hook handles this; bow out to avoid
# emitting the same diagnostics twice (Antigravity runs every hook in the list).
if (Get-Command bash -ErrorAction SilentlyContinue) { exit 0 }

$InstallDir = if ($env:MONK_AGENT_INSTALL_DIR) { $env:MONK_AGENT_INSTALL_DIR } else { Join-Path $HOME ".monk\bin" }
$agent = if ($env:MONK_AGENT_PATH) { $env:MONK_AGENT_PATH } else { Join-Path $InstallDir "monk-agent.exe" }

if (-not (Test-Path $agent)) { exit 0 }

try { $hookInput | & $agent hook diagnostics --format antigravity } catch { }
exit 0
