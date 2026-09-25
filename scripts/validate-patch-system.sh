#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then reset='\033[0m'; bold='\033[1m'; cyan='\033[36m'; green='\033[32m'; red='\033[31m'; else reset=''; bold=''; cyan=''; green=''; red=''; fi
log(){ local l="$1" m="$2" c="$cyan"; [[ "$l" == OK ]]&&c="$green"; [[ "$l" == ERROR ]]&&c="$red"; printf '%b[NEXALI][PATCH-SYSTEM]%b %b[%s]%b %s\n' "$bold" "$reset" "$c" "$l" "$reset" "$m"; }
die(){ log ERROR "$1" >&2; exit 1; }

required=(
  eng/patch/project.json
  eng/patch/manifest.schema.json
  scripts/patch/patchlib.py
  scripts/patch/engine.py
  scripts/patch/engine.sh
  scripts/patch/patchctl.sh
  scripts/patch/build-package.py
  scripts/patch/tests/test_patchlib.py
  docs/development/patch-workflow.md
)
log CHECK "Checking durable patch-system baseline files."
for path in "${required[@]}"; do [[ -f "$repo_root/$path" ]] || die "Missing file: $path"; done
for path in scripts/patch/engine.py scripts/patch/engine.sh scripts/patch/patchctl.sh scripts/patch/build-package.py; do
  [[ -x "$repo_root/$path" ]] || die "File is not executable: $path"
done

grep -Fxq '.work/' "$repo_root/.gitignore" || die ".gitignore must ignore .work/."

log CHECK "Checking Bash and Python syntax without writing bytecode artifacts."
bash -n "$repo_root/scripts/patch/engine.sh" "$repo_root/scripts/patch/patchctl.sh"
python3 - \
  "$repo_root/scripts/patch/patchlib.py" \
  "$repo_root/scripts/patch/engine.py" \
  "$repo_root/scripts/patch/build-package.py" \
  "$repo_root/scripts/patch/tests/test_patchlib.py" <<'PY'
from pathlib import Path
import sys
for raw in sys.argv[1:]:
    path = Path(raw)
    source = path.read_text(encoding='utf-8')
    compile(source, str(path), 'exec')
PY

log CHECK "Running patch-library unit tests."
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$repo_root/scripts/patch/tests" -p 'test_*.py' -v >/dev/null

log CHECK "Running engine pure self-test."
PYTHONDONTWRITEBYTECODE=1 python3 "$repo_root/scripts/patch/engine.py" self-test >/dev/null

log CHECK "Validating project identity and version scheme."
python3 - "$repo_root/eng/patch/project.json" "$repo_root/eng/patch/manifest.schema.json" <<'PY'
import json, re, sys
project=json.load(open(sys.argv[1],encoding='utf-8'))
schema=json.load(open(sys.argv[2],encoding='utf-8'))
assert project['schemaVersion']==1
assert project['id']=='nexali'
assert project['guid']=='492c51d4-032f-5d3b-bc45-47656b1b47de'
assert project['repository']=='alescis-wuin/nexali'
assert project['integrationBranch']=='develop'
assert project['versioning']['format']=='X.Y.Z'
assert schema['properties']['schemaVersion']['const']==1
assert re.fullmatch(r'[0-9a-f-]{36}', project['guid'])
PY

log OK "Nexali durable patch-system baseline validation passed."
