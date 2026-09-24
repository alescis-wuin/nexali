#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
solution="$repo_root/Nexali.sln"
layout="$repo_root/eng/solution-folders.txt"
mode="${1:-}"

if [[ $# -gt 1 || ( -n "$mode" && "$mode" != "--normalize" ) ]]; then
  echo "Usage: $0 [--normalize]" >&2
  exit 2
fi

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; yellow='\033[33m'; red='\033[31m'
else
  reset=''; bold=''; cyan=''; green=''; yellow=''; red=''
fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == WARN ]]&&c="$yellow"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][SOLUTION]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

log CHECK "Checking canonical solution files."
[[ -f "$solution" ]] || die "Missing solution: Nexali.sln"
[[ -f "$layout" ]] || die "Missing solution-folder manifest: eng/solution-folders.txt"
if find "$repo_root" -maxdepth 1 -type f -name '*.slnx' -print -quit | grep -q .; then
  die "Unexpected .slnx file found at repository root; Nexali.sln is canonical."
fi
command -v python3 >/dev/null 2>&1 || die "python3 is required by the solution encoding validator."

if [[ "$mode" == "--normalize" ]]; then
  python3 - "$solution" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
expected = "Microsoft Visual Studio Solution File, Format Version 12.00"
data = path.read_bytes()

if data.startswith(b"\xef\xbb\xbf"):
    data = data[3:]

if data.startswith((b"\xff\xfe", b"\xfe\xff")):
    text = data.decode("utf-16")
else:
    try:
        text = data.decode("utf-8")
    except UnicodeDecodeError as exc:
        print(f"[NEXALI][SOLUTION][ERROR] Nexali.sln is not valid UTF-8/UTF-16 text: {exc}", file=sys.stderr)
        sys.exit(1)

text = text.replace("\r\n", "\n").replace("\r", "\n")
lines = text.split("\n")
while lines and not lines[0].strip():
    lines.pop(0)

if not lines or lines[0] != expected:
    first = lines[0] if lines else "<missing>"
    preview = data[:48].hex(" ")
    print(f"[NEXALI][SOLUTION][ERROR] Cannot normalize unexpected SLN header: {first!r}", file=sys.stderr)
    print(f"[NEXALI][SOLUTION][ERROR] First bytes: {preview}", file=sys.stderr)
    sys.exit(1)

normalized = "\n".join(lines)
normalized = normalized.rstrip("\n") + "\n"
path.write_bytes(normalized.encode("utf-8"))
PY
  log OK "Nexali.sln normalized to UTF-8 without BOM and LF line endings."
fi

python3 - "$solution" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
expected = "Microsoft Visual Studio Solution File, Format Version 12.00"
data = path.read_bytes()
errors = []
if data.startswith(b"\xef\xbb\xbf"):
    errors.append("UTF-8 BOM is present")
if data.startswith((b"\xff\xfe", b"\xfe\xff")):
    errors.append("UTF-16 BOM is present")
if b"\r" in data:
    errors.append("CR/CRLF line endings are present")
try:
    text = data.decode("utf-8")
except UnicodeDecodeError as exc:
    errors.append(f"invalid UTF-8: {exc}")
    text = ""
first = text.split("\n", 1)[0] if text else ""
if first != expected:
    errors.append(f"unexpected first line: {first!r}")
if errors:
    print("[NEXALI][SOLUTION][ERROR] Nexali.sln byte-level validation failed: " + "; ".join(errors), file=sys.stderr)
    print("[NEXALI][SOLUTION][ERROR] First bytes: " + data[:48].hex(" "), file=sys.stderr)
    sys.exit(1)
PY

[[ "$(head -n 1 "$solution")" == 'Microsoft Visual Studio Solution File, Format Version 12.00' ]] || die "Unexpected Nexali.sln format header."
grep -Fqx '# Visual Studio Version 17' "$solution" || die "Missing Visual Studio 17 marker."
grep -Fq 'Debug|Any CPU = Debug|Any CPU' "$solution" || die "Missing Debug|Any CPU."
grep -Fq 'Release|Any CPU = Release|Any CPU' "$solution" || die "Missing Release|Any CPU."
grep -Fq 'HideSolutionNode = FALSE' "$solution" || die "Solution node must remain visible."
log OK "SLN structure, encoding, and configurations are valid."

expected=('src/Server' 'src/Modules' 'src/Libraries' 'src/Clients/Web' 'src/Clients/Avalonia' 'src/Tools' 'tests')
mapfile -t actual < <(grep -Ev '^[[:space:]]*(#|$)' "$layout")
[[ "${#actual[@]}" -eq "${#expected[@]}" ]] || die "Unexpected solution-folder manifest size."
for i in "${!expected[@]}"; do
  [[ "${actual[$i]}" == "${expected[$i]}" ]] || die "Solution-folder manifest mismatch at entry $((i+1))."
done
log OK "Solution-folder plan is pinned and valid."

if command -v dotnet >/dev/null 2>&1; then
  sdk="$(dotnet --version 2>/dev/null || true)"
  log CHECK "Validating Nexali.sln with .NET SDK ${sdk:-unknown}."
  DOTNET_NOLOGO=1 DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1 dotnet sln "$solution" list >/dev/null || die "The installed .NET SDK could not parse Nexali.sln."
  log OK ".NET CLI accepts Nexali.sln."
else
  log WARN ".NET SDK not found; CLI parsing check skipped."
fi
log OK "Nexali solution baseline validation passed."
