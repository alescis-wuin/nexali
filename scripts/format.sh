#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mode="apply"
if [[ "${1:-}" == "--check" ]]; then mode="check"; shift; fi
[[ $# -eq 0 ]] || { echo "Usage: $0 [--check]" >&2; exit 2; }
command -v dotnet >/dev/null 2>&1 || { echo "[NEXALI][FORMAT][ERROR] dotnet is required." >&2; exit 1; }
cd "$repo_root"
DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 dotnet restore Nexali.sln --nologo >/dev/null
common=(Nexali.sln --no-restore --verbosity minimal)
if [[ "$mode" == "check" ]]; then
  echo "[NEXALI][FORMAT][CHECK] Verifying deterministic repository whitespace formatting."
  DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    dotnet format whitespace "${common[@]}" --verify-no-changes
  echo "[NEXALI][FORMAT][OK] No whitespace formatting changes are required."
else
  echo "[NEXALI][FORMAT][STEP] Applying deterministic whitespace formatting."
  DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    dotnet format whitespace "${common[@]}"
  echo "[NEXALI][FORMAT][STEP] Applying warning-level automatic code-style fixes when Roslyn exposes a safe code fix."
  DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 \
    dotnet format style "${common[@]}" --severity warn
  echo "[NEXALI][FORMAT][OK] Formatting and available warning-level style fixes completed."
fi
