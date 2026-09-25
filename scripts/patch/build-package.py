#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import tempfile
import zipfile
from pathlib import Path

from patchlib import PatchError, sha256_bytes, validate_manifest
import json

LAUNCHER = r'''#!/usr/bin/env bash
set -Eeuo pipefail
if [[ -z "${BASH_VERSION:-}" ]]; then
  printf '[NEXALI][PATCH][ERROR] This package must be launched with Bash.\n' >&2
  exit 1
fi
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  printf '[NEXALI][PATCH][ERROR] Current directory is not inside a Git repository. Enter the target project and rerun the same command.\n' >&2
  exit 1
}
engine="$repo_root/scripts/patch/engine.sh"
if [[ ! -x "$engine" ]]; then
  printf '[NEXALI][PATCH][ERROR] Durable patch engine is not installed in this repository: %s\n' "$engine" >&2
  exit 1
fi
exec "$engine" apply --package "$0"
exit 127
'''.encode("utf-8")

FIXED_ZIP_TIME = (2026, 1, 1, 0, 0, 0)


def add_bytes(zf: zipfile.ZipFile, name: str, data: bytes, mode: int = 0o644) -> None:
    info = zipfile.ZipInfo(name, FIXED_ZIP_TIME)
    info.compress_type = zipfile.ZIP_DEFLATED
    info.external_attr = (mode & 0xFFFF) << 16
    info.create_system = 3
    zf.writestr(info, data, compresslevel=9)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build a deterministic Nexali self-extracting patch ZIP")
    parser.add_argument("--package-dir", required=True)
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    package_dir = Path(args.package_dir).resolve()
    manifest_path = package_dir / "manifest.json"
    payload_dir = package_dir / "payload"
    if not manifest_path.is_file() or not payload_dir.is_dir():
        raise PatchError("Package source must contain manifest.json and payload/.")
    manifest_bytes = manifest_path.read_bytes()
    manifest = json.loads(manifest_bytes.decode("utf-8"))
    validate_manifest(manifest)

    files: dict[str, bytes] = {"patch/manifest.json": manifest_bytes}
    for operation in manifest["operations"]:
        if operation["type"] not in ("add", "replace"):
            continue
        source = operation["source"]
        path = package_dir / source
        if not path.is_file() or path.is_symlink():
            raise PatchError(f"Payload source missing/non-regular: {source}")
        data = path.read_bytes()
        digest = sha256_bytes(data)
        if digest != operation["afterSha256"]:
            raise PatchError(f"afterSha256 mismatch for {source}: manifest={operation['afterSha256']} actual={digest}")
        files["patch/" + source] = data

    checksum_lines = [f"{sha256_bytes(data)}  {name}" for name, data in sorted(files.items())]
    files["patch/SHA256SUMS"] = ("\n".join(checksum_lines) + "\n").encode("utf-8")

    output = Path(args.output).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix="nexali-patch-", suffix=".zip", delete=False) as temp:
        temp_path = Path(temp.name)
    try:
        with zipfile.ZipFile(temp_path, "w") as zf:
            for name, data in sorted(files.items()):
                add_bytes(zf, name, data)
        output.write_bytes(LAUNCHER + b"\n" + temp_path.read_bytes())
        os.chmod(output, 0o644)
    finally:
        temp_path.unlink(missing_ok=True)
    print(output)
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (PatchError, json.JSONDecodeError, UnicodeDecodeError) as exc:
        print(f"[NEXALI][PATCH-BUILD][ERROR] {exc}", file=__import__("sys").stderr)
        raise SystemExit(1)
