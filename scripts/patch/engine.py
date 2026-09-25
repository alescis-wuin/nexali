#!/usr/bin/env python3
from __future__ import annotations

import argparse
import errno
import fcntl
import json
import os
import queue
import shutil
import signal
import stat
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import zipfile
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
from typing import Any, Iterable

from patchlib import (
    PatchError,
    atomic_write_json,
    load_json,
    normalize_github_origin,
    parse_version,
    safe_rel_path,
    sha256_bytes,
    sha256_file,
    validate_manifest,
)

ENGINE_VERSION = "1.0.0"
WORK_REL = Path(".work/patch-engine")
PROJECT_CONFIG_REL = Path("eng/patch/project.json")
APPLIED_RECEIPTS_REL = Path("eng/patch/applied")


def now_utc() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def now_local() -> str:
    return datetime.now().astimezone().isoformat(timespec="milliseconds")


def run_quiet(argv: list[str], cwd: Path, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(argv, cwd=cwd, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if check and result.returncode != 0:
        raise PatchError(f"Command failed ({result.returncode}): {' '.join(argv)}\n{result.stderr.strip()}")
    return result


def git(repo: Path, *args: str, check: bool = True) -> str:
    result = run_quiet(["git", *args], repo, check=check)
    return result.stdout.strip()


def find_repo_from_cwd() -> Path:
    result = subprocess.run(["git", "rev-parse", "--show-toplevel"], text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if result.returncode != 0:
        raise PatchError("Current directory is not inside a Git worktree. Enter the Nexali repository (or one of its subdirectories) and retry the same one-command patch.")
    root = Path(result.stdout.strip()).resolve()
    cwd = Path.cwd().resolve()
    try:
        cwd.relative_to(root)
    except ValueError as exc:
        raise PatchError(f"Current directory {cwd} is not inside repository {root}.") from exc
    return root


def supports_color() -> bool:
    if not sys.stdout.isatty() or os.environ.get("NO_COLOR") or os.environ.get("TERM") in (None, "", "dumb"):
        return False
    if shutil.which("tput") is None:
        return False
    try:
        result = subprocess.run(["tput", "colors"], text=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=2)
        return result.returncode == 0 and int(result.stdout.strip() or "0") >= 8
    except (ValueError, OSError, subprocess.SubprocessError):
        return False


class Logger:
    COLORS = {
        "TRACE": "\033[90m",
        "DEBUG": "\033[36m",
        "INFO": "\033[37m",
        "STEP": "\033[1;34m",
        "CHECK": "\033[35m",
        "OK": "\033[1;32m",
        "WARN": "\033[1;33m",
        "ERROR": "\033[1;31m",
        "CMD": "\033[90m",
    }
    RESET = "\033[0m"

    def __init__(self, version: str, txid: str, report_dir: Path | None = None) -> None:
        self.version = version
        self.txid = txid
        self.report_dir = report_dir
        self.color = supports_color()
        self._lock = threading.Lock()
        self._events = None
        self._console = None
        self._console_ansi = None
        if report_dir is not None:
            report_dir.mkdir(parents=True, exist_ok=True)
            self._events = (report_dir / "events.jsonl").open("a", encoding="utf-8", buffering=1)
            self._console = (report_dir / "console.log").open("a", encoding="utf-8", buffering=1)
            self._console_ansi = (report_dir / "console.ansi.log").open("a", encoding="utf-8", buffering=1)

    def attach_report(self, report_dir: Path) -> None:
        with self._lock:
            self.close()
            self.report_dir = report_dir
            report_dir.mkdir(parents=True, exist_ok=True)
            self._events = (report_dir / "events.jsonl").open("a", encoding="utf-8", buffering=1)
            self._console = (report_dir / "console.log").open("a", encoding="utf-8", buffering=1)
            self._console_ansi = (report_dir / "console.ansi.log").open("a", encoding="utf-8", buffering=1)

    def close(self) -> None:
        for fh in (self._events, self._console, self._console_ansi):
            if fh is not None:
                try:
                    fh.flush()
                    fh.close()
                except OSError:
                    pass
        self._events = self._console = self._console_ansi = None

    def emit(self, level: str, message: str, component: str = "ENGINE") -> None:
        local_ts = now_local()
        plain = f"[{local_ts}][NEXALI][PATCH {self.version}][{component}][{level}][TX {self.txid}] {message}"
        colored = plain
        if self.color and level in self.COLORS:
            colored = f"{self.COLORS[level]}{plain}{self.RESET}"
        event = {
            "timestamp": now_utc(),
            "localTimestamp": local_ts,
            "project": "nexali",
            "patchVersion": self.version,
            "transactionId": self.txid,
            "component": component,
            "level": level,
            "message": message,
        }
        with self._lock:
            print(colored, flush=True)
            if self._console is not None:
                self._console.write(plain + "\n")
            if self._console_ansi is not None:
                self._console_ansi.write(colored + "\n")
            if self._events is not None:
                self._events.write(json.dumps(event, ensure_ascii=False, sort_keys=True) + "\n")


class WorkLock:
    def __init__(self, path: Path) -> None:
        self.path = path
        self.fh = None

    def __enter__(self) -> "WorkLock":
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.fh = self.path.open("a+")
        try:
            fcntl.flock(self.fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError as exc:
            if exc.errno in (errno.EACCES, errno.EAGAIN):
                raise PatchError("Another patch transaction is already running for this repository.") from exc
            raise
        self.fh.seek(0)
        self.fh.truncate(0)
        self.fh.write(f"pid={os.getpid()} started={now_utc()}\n")
        self.fh.flush()
        return self

    def __exit__(self, exc_type: Any, exc: Any, tb: Any) -> None:
        if self.fh is not None:
            try:
                fcntl.flock(self.fh.fileno(), fcntl.LOCK_UN)
            finally:
                self.fh.close()


def safe_zip_members(zf: zipfile.ZipFile) -> list[zipfile.ZipInfo]:
    infos = zf.infolist()
    if not infos:
        raise PatchError("Patch archive is empty.")
    total = 0
    for info in infos:
        name = info.filename
        if "\x00" in name or "\\" in name:
            raise PatchError(f"Unsafe ZIP member: {name!r}")
        p = PurePosixPath(name)
        if p.is_absolute() or any(part in ("", ".", "..") for part in p.parts):
            raise PatchError(f"Unsafe ZIP member: {name!r}")
        mode = (info.external_attr >> 16) & 0o170000
        if mode == stat.S_IFLNK:
            raise PatchError(f"Symlink ZIP members are forbidden: {name}")
        total += info.file_size
        if info.file_size > 128 * 1024 * 1024:
            raise PatchError(f"ZIP member exceeds 128 MiB safety limit: {name}")
    if total > 512 * 1024 * 1024:
        raise PatchError("Uncompressed patch archive exceeds 512 MiB safety limit.")
    return infos


def read_package(package: Path) -> tuple[dict[str, Any], dict[str, str]]:
    try:
        with zipfile.ZipFile(package) as zf:
            safe_zip_members(zf)
            manifest = json.loads(zf.read("patch/manifest.json").decode("utf-8"))
            validate_manifest(manifest)
            checksum_text = zf.read("patch/SHA256SUMS").decode("utf-8")
            checksums: dict[str, str] = {}
            for raw in checksum_text.splitlines():
                if not raw.strip():
                    continue
                digest, sep, name = raw.partition("  ")
                if not sep or len(digest) != 64:
                    raise PatchError("Malformed patch/SHA256SUMS entry.")
                checksums[name] = digest
            required = {"patch/manifest.json"}
            for op in manifest["operations"]:
                if op["type"] in ("add", "replace"):
                    required.add("patch/" + op["source"])
            for name in sorted(required):
                if name not in checksums:
                    raise PatchError(f"Missing checksum entry for {name}")
                actual = sha256_bytes(zf.read(name))
                if actual != checksums[name]:
                    raise PatchError(f"Embedded checksum mismatch for {name}")
            return manifest, checksums
    except (OSError, KeyError, zipfile.BadZipFile, json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise PatchError(f"Invalid patch archive {package}: {exc}") from exc


def extract_payload_file(package: Path, member: str) -> bytes:
    with zipfile.ZipFile(package) as zf:
        return zf.read("patch/" + member)


def ensure_no_symlink_components(repo: Path, rel: str) -> Path:
    safe = safe_rel_path(rel)
    current = repo
    for part in safe.parts[:-1]:
        current = current / part
        if current.exists() and current.is_symlink():
            raise PatchError(f"Symlinked repository path component is forbidden: {current}")
    target = repo.joinpath(*safe.parts)
    if target.exists() and target.is_symlink():
        raise PatchError(f"Symlink patch target is forbidden: {target}")
    return target


def project_identity(repo: Path) -> dict[str, Any]:
    path = repo / PROJECT_CONFIG_REL
    if not path.is_file():
        raise PatchError(f"Patch engine project identity is missing: {PROJECT_CONFIG_REL}")
    data = load_json(path)
    if data.get("schemaVersion") != 1:
        raise PatchError("Unsupported project patch identity schema.")
    return data


def verify_project(repo: Path, manifest: dict[str, Any]) -> None:
    identity = project_identity(repo)
    expected = manifest["project"]
    for field in ("id", "guid", "repository"):
        if identity.get(field) != expected.get(field):
            raise PatchError(f"Patch project mismatch for {field}: expected {expected.get(field)!r}, repository has {identity.get(field)!r}.")
    origin = git(repo, "remote", "get-url", "origin")
    normalized = normalize_github_origin(origin)
    if normalized != expected["repository"]:
        raise PatchError(f"origin points to {origin!r}, not expected GitHub repository {expected['repository']!r}.")


def git_visible_changes(repo: Path) -> set[str]:
    result: set[str] = set()
    for argv in (
        ["git", "diff", "--name-only", "-z"],
        ["git", "diff", "--cached", "--name-only", "-z"],
        ["git", "ls-files", "--others", "--exclude-standard", "-z"],
    ):
        cp = subprocess.run(argv, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if cp.returncode != 0:
            continue
        for item in cp.stdout.split(b"\0"):
            if item:
                result.add(item.decode("utf-8", "surrogateescape"))
    return result


class MutationWatcher:
    def __init__(self, repo: Path, allowed: set[str], logger: Logger) -> None:
        self.repo = repo
        self.allowed = allowed
        self.logger = logger
        self.stop_event = threading.Event()
        self.violation = threading.Event()
        self.paths: set[str] = set()
        self.thread = threading.Thread(target=self._run, name="nexali-patch-watcher", daemon=True)

    def _run(self) -> None:
        while not self.stop_event.wait(1.0):
            changed = git_visible_changes(self.repo)
            unexpected = changed - self.allowed
            if unexpected:
                self.paths.update(unexpected)
                self.violation.set()
                return

    def start(self) -> None:
        self.thread.start()

    def stop(self) -> None:
        self.stop_event.set()
        self.thread.join(timeout=3)

    def assert_clean(self) -> None:
        if self.violation.is_set():
            raise PatchError("External/unowned worktree mutation detected: " + ", ".join(sorted(self.paths)))


def snapshot(repo: Path, report: Path, label: str) -> None:
    root = report / "snapshots" / label
    (root / "git").mkdir(parents=True, exist_ok=True)
    (root / "filesystem").mkdir(parents=True, exist_ok=True)

    commands = {
        "status-porcelain-v2.txt": ["git", "status", "--porcelain=v2", "--branch", "--untracked-files=all"],
        "status-short.txt": ["git", "status", "--short", "--branch"],
        "log.txt": ["git", "--no-pager", "log", "-30", "--date=iso-strict", "--decorate", "--pretty=format:%H%x09%ad%x09%d%x09%s"],
        "branch-vv.txt": ["git", "branch", "-vv"],
        "remote-v.txt": ["git", "remote", "-v"],
        "diff.patch": ["git", "--no-pager", "diff", "--binary", "--full-index"],
        "diff-cached.patch": ["git", "--no-pager", "diff", "--cached", "--binary", "--full-index"],
        "show-head.txt": ["git", "--no-pager", "show", "--stat", "--summary", "--decorate", "HEAD"],
    }
    for name, argv in commands.items():
        cp = subprocess.run(argv, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (root / "git" / name).write_bytes(cp.stdout)

    tracked_raw = subprocess.check_output(["git", "ls-files", "-z"], cwd=repo)
    untracked_raw = subprocess.check_output(["git", "ls-files", "--others", "--exclude-standard", "-z"], cwd=repo)
    tracked = [x.decode("utf-8", "surrogateescape") for x in tracked_raw.split(b"\0") if x]
    untracked = [x.decode("utf-8", "surrogateescape") for x in untracked_raw.split(b"\0") if x]
    all_paths = sorted(set(tracked + untracked))

    def tree_lines(paths: Iterable[str]) -> list[str]:
        node: dict[str, Any] = {}
        for path in paths:
            cur = node
            parts = PurePosixPath(path).parts
            for part in parts:
                cur = cur.setdefault(part, {})
        lines: list[str] = ["."]
        def walk(mapping: dict[str, Any], prefix: str) -> None:
            items = sorted(mapping.items())
            for idx, (name, child) in enumerate(items):
                last = idx == len(items) - 1
                lines.append(prefix + ("└── " if last else "├── ") + name)
                if child:
                    walk(child, prefix + ("    " if last else "│   "))
        walk(node, "")
        return lines

    (root / "filesystem" / "tree.txt").write_text("\n".join(tree_lines(all_paths)) + "\n", encoding="utf-8")
    (root / "filesystem" / "untracked-files.txt").write_text("\n".join(sorted(untracked)) + ("\n" if untracked else ""), encoding="utf-8")
    rows = ["path\tsize_bytes\tmode\tmtime_utc\tsha256"]
    sums: list[str] = []
    for rel in sorted(tracked):
        path = repo / rel
        if not path.is_file() or path.is_symlink():
            continue
        st = path.stat()
        digest = sha256_file(path)
        mtime = datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(timespec="seconds").replace("+00:00", "Z")
        mode = format(stat.S_IMODE(st.st_mode), "04o")
        rows.append(f"{rel}\t{st.st_size}\t{mode}\t{mtime}\t{digest}")
        sums.append(f"{digest}  {rel}")
    (root / "filesystem" / "files.tsv").write_text("\n".join(rows) + "\n", encoding="utf-8")
    (root / "filesystem" / "manifest.sha256").write_text("\n".join(sums) + "\n", encoding="utf-8")


def environment_report(report: Path, repo: Path) -> None:
    env_dir = report / "environment"
    env_dir.mkdir(parents=True, exist_ok=True)
    commands = {
        "uname.txt": ["uname", "-a"],
        "bash-version.txt": ["bash", "--version"],
        "git-version.txt": ["git", "--version"],
        "python-version.txt": ["python3", "--version"],
        "df.txt": ["df", "-h", str(repo)],
    }
    if shutil.which("dotnet"):
        commands["dotnet-info.txt"] = ["dotnet", "--info"]
    for name, argv in commands.items():
        cp = subprocess.run(argv, cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        (env_dir / name).write_bytes(cp.stdout)
    safe_env = {k: os.environ.get(k, "") for k in ("LANG", "LC_ALL", "TERM", "SHELL", "NO_COLOR", "CI")}
    (env_dir / "environment-whitelist.json").write_text(json.dumps(safe_env, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def run_streamed(argv: list[str], cwd: Path, logger: Logger, step_log: Path, timeout: int) -> None:
    step_log.parent.mkdir(parents=True, exist_ok=True)
    logger.emit("CMD", "$ " + " ".join(argv), component="RUN")
    env = os.environ.copy()
    env.setdefault("DOTNET_NOLOGO", "1")
    env.setdefault("DOTNET_CLI_TELEMETRY_OPTOUT", "1")
    proc = subprocess.Popen(
        argv,
        cwd=cwd,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    assert proc.stdout is not None
    q: queue.Queue[str | None] = queue.Queue()

    def reader() -> None:
        try:
            for line in proc.stdout:
                q.put(line.rstrip("\n"))
        finally:
            q.put(None)

    thread = threading.Thread(target=reader, daemon=True)
    thread.start()
    start = time.monotonic()
    eof = False
    with step_log.open("w", encoding="utf-8", buffering=1) as raw:
        while not eof or proc.poll() is None:
            if time.monotonic() - start > timeout:
                logger.emit("ERROR", f"Command exceeded timeout of {timeout}s; terminating process group.", component="RUN")
                try:
                    os.killpg(proc.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    try:
                        os.killpg(proc.pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                raise PatchError(f"Command timed out after {timeout}s: {' '.join(argv)}")
            try:
                item = q.get(timeout=0.2)
            except queue.Empty:
                continue
            if item is None:
                eof = True
                continue
            raw.write(item + "\n")
            logger.emit("CMD", item, component="OUTPUT")
    rc = proc.wait()
    thread.join(timeout=2)
    if rc != 0:
        raise PatchError(f"Command failed with exit code {rc}: {' '.join(argv)}")


def copy_archive_verified(source: Path, destination: Path, expected_sha: str) -> Path:
    destination.parent.mkdir(parents=True, exist_ok=True)
    tmp = destination.with_name("." + destination.name + ".tmp")
    if tmp.exists():
        tmp.unlink()
    shutil.copy2(source, tmp)
    if sha256_file(tmp) != expected_sha:
        tmp.unlink(missing_ok=True)
        raise PatchError("Package copy into .work failed checksum verification.")
    os.replace(tmp, destination)
    if source.resolve() != destination.resolve():
        downloads = (Path.home() / "Téléchargements").resolve()
        try:
            source.resolve().relative_to(downloads)
        except ValueError:
            pass
        else:
            source.unlink()
    return destination


def check_package_duplicate(repo: Path, work: Path, version: str, package_sha: str) -> None:
    version_receipt = repo / APPLIED_RECEIPTS_REL / f"{version}.json"
    if version_receipt.exists():
        raise PatchError(f"Patch {version} is already recorded as applied in {version_receipt.relative_to(repo)}.")
    local_applied = work / "state" / "applied"
    if local_applied.exists():
        for receipt_path in local_applied.glob("*.json"):
            try:
                receipt = load_json(receipt_path)
            except PatchError:
                continue
            if receipt.get("version") == version:
                raise PatchError(f"Patch {version} was already applied locally (transaction {receipt.get('transactionId')}).")
            if receipt.get("packageSha256") == package_sha:
                raise PatchError(f"This exact package archive was already applied as patch {receipt.get('version')}.")


def assert_prerequisites(repo: Path, manifest: dict[str, Any]) -> None:
    for version in manifest["patch"].get("requires", []):
        path = repo / APPLIED_RECEIPTS_REL / f"{version}.json"
        if not path.is_file():
            raise PatchError(f"Required predecessor patch {version} is not recorded in {APPLIED_RECEIPTS_REL}.")


def backup_paths(repo: Path, backup: Path, paths: Iterable[str]) -> dict[str, Any]:
    metadata: dict[str, Any] = {"createdAt": now_utc(), "paths": {}}
    files_root = backup / "files"
    for rel in sorted(set(paths)):
        target = repo / rel
        entry: dict[str, Any] = {"existed": target.exists()}
        if target.exists():
            if target.is_symlink() or not target.is_file():
                raise PatchError(f"Backup target is not a regular file: {rel}")
            data = target.read_bytes()
            dest = files_root / rel
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data)
            os.chmod(dest, stat.S_IMODE(target.stat().st_mode))
            entry.update({"sha256": sha256_bytes(data), "mode": format(stat.S_IMODE(target.stat().st_mode), "04o")})
        metadata["paths"][rel] = entry
    atomic_write_json(backup / "backup.json", metadata)
    return metadata


def restore_backup(repo: Path, backup: Path, metadata: dict[str, Any]) -> None:
    for rel, entry in metadata["paths"].items():
        target = repo / rel
        if entry["existed"]:
            source = backup / "files" / rel
            target.parent.mkdir(parents=True, exist_ok=True)
            tmp = target.with_name("." + target.name + ".restore")
            shutil.copy2(source, tmp)
            os.chmod(tmp, int(entry["mode"], 8))
            os.replace(tmp, target)
        else:
            if target.exists():
                if target.is_file() and not target.is_symlink():
                    target.unlink()
                else:
                    raise PatchError(f"Rollback refuses to remove non-regular path: {rel}")
    # Remove empty directories created by new files, excluding durable roots.
    for rel, entry in sorted(metadata["paths"].items(), key=lambda kv: len(PurePosixPath(kv[0]).parts), reverse=True):
        if entry["existed"]:
            continue
        parent = (repo / rel).parent
        while parent != repo and parent not in (repo / "eng", repo / "scripts", repo / "docs"):
            try:
                parent.rmdir()
            except OSError:
                break
            parent = parent.parent


def apply_operations(repo: Path, package: Path, manifest: dict[str, Any]) -> list[str]:
    changed: list[str] = []
    for operation in manifest["operations"]:
        rel = operation["path"]
        target = ensure_no_symlink_components(repo, rel)
        op_type = operation["type"]
        if op_type in ("replace", "delete"):
            if not target.is_file() or target.is_symlink():
                raise PatchError(f"Expected existing regular file for {op_type}: {rel}")
            actual_before = sha256_file(target)
            if actual_before != operation["beforeSha256"]:
                raise PatchError(f"Preimage checksum mismatch for {rel}: expected {operation['beforeSha256']}, got {actual_before}")
        if op_type == "add" and target.exists():
            raise PatchError(f"Add operation target already exists: {rel}")
        if op_type == "delete":
            target.unlink()
            changed.append(rel)
            continue
        data = extract_payload_file(package, operation["source"])
        if sha256_bytes(data) != operation["afterSha256"]:
            raise PatchError(f"Payload postimage checksum mismatch for {rel}")
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name("." + target.name + ".patchtmp")
        tmp.write_bytes(data)
        os.chmod(tmp, int(operation.get("mode", "0644"), 8))
        os.replace(tmp, target)
        changed.append(rel)
    return changed


def write_versioned_receipt(repo: Path, manifest: dict[str, Any], txid: str, package_sha: str, base_sha: str) -> Path:
    version = manifest["patch"]["version"]
    receipt_path = repo / APPLIED_RECEIPTS_REL / f"{version}.json"
    receipt = {
        "schemaVersion": 1,
        "projectId": manifest["project"]["id"],
        "projectGuid": manifest["project"]["guid"],
        "version": version,
        "name": manifest["patch"]["name"],
        "packageSha256": package_sha,
        "transactionId": txid,
        "baseCommit": base_sha,
        "topicBranch": manifest["git"]["topicBranch"],
        "appliedAt": now_utc(),
    }
    atomic_write_json(receipt_path, receipt, mode=0o644)
    return receipt_path


def write_report_summary(report: Path, state: dict[str, Any], manifest: dict[str, Any]) -> None:
    result = state.get("result", "unknown")
    lines = [
        f"# Nexali patch report — {manifest['patch']['version']}",
        "",
        f"- Result: **{result}**",
        f"- Patch: `{manifest['patch']['version']}` — `{manifest['patch']['name']}`",
        f"- Transaction: `{state['transactionId']}`",
        f"- Started: `{state['startedAt']}`",
        f"- Finished: `{state.get('finishedAt', '')}`",
        f"- Base: `{state.get('baseCommit', '')}`",
        f"- Topic branch: `{manifest['git']['topicBranch']}`",
        f"- Commit: `{state.get('commit', '')}`",
        f"- Package SHA-256: `{state.get('packageSha256', '')}`",
        "",
        "## Evidence",
        "",
        "- `console.log`: plain console transcript.",
        "- `console.ansi.log`: terminal-color transcript.",
        "- `events.jsonl`: structured event stream.",
        "- `steps/`: raw command output per validation.",
        "- `snapshots/before` and `snapshots/after`: Git state, tree, checksums, sizes, modes and mtimes.",
        "- `environment/`: toolchain and safe environment information.",
        "- `package/`: manifest and package checksums.",
        "- `state/`: transaction state snapshots.",
    ]
    if state.get("error"):
        lines.extend(["", "## Error", "", f"`{state['error']}`"])
    (report / "report.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    atomic_write_json(report / "report.json", state)


def update_tx_state(state_path: Path, report: Path, state: dict[str, Any], phase: str, **extra: Any) -> None:
    state["phase"] = phase
    state["updatedAt"] = now_utc()
    state.update(extra)
    atomic_write_json(state_path, state)
    state_copy = report / "state" / f"{len(list((report / 'state').glob('*.json'))):03d}-{phase}.json"
    atomic_write_json(state_copy, state)


def cmd_status(repo: Path) -> int:
    identity = project_identity(repo)
    work = repo / WORK_REL
    print(json.dumps({
        "project": identity,
        "repositoryRoot": str(repo),
        "branch": git(repo, "branch", "--show-current"),
        "head": git(repo, "rev-parse", "HEAD"),
        "appliedVersionReceipts": sorted(p.stem for p in (repo / APPLIED_RECEIPTS_REL).glob("*.json")),
        "localStatePresent": work.exists(),
    }, indent=2, sort_keys=True))
    return 0


def cmd_self_test() -> int:
    from patchlib import parse_version, safe_rel_path
    assert parse_version("1.8.1") == (1, 8, 1)
    for invalid in ("1.08.1", "v1.8.1", "1.8", "1.8.1.0"):
        try:
            parse_version(invalid)
        except PatchError:
            pass
        else:
            raise AssertionError(f"invalid version accepted: {invalid}")
    for invalid in ("../x", "/x", ".git/config", ".work/x"):
        try:
            safe_rel_path(invalid)
        except PatchError:
            pass
        else:
            raise AssertionError(f"unsafe path accepted: {invalid}")
    print("[OK] patch engine self-test passed")
    return 0


def cmd_cleanup(repo: Path, apply: bool) -> int:
    identity = project_identity(repo)
    retention = identity.get("retention", {})
    work = repo / WORK_REL
    targets = [
        (work / "packages" / "applied", int(retention.get("appliedPackages", 20))),
        (work / "packages" / "failed", int(retention.get("failedPackages", 20))),
        (work / "reports", int(retention.get("reports", 30))),
    ]
    removed: list[str] = []
    for directory, keep in targets:
        if not directory.exists():
            continue
        entries = sorted(directory.iterdir(), key=lambda p: p.stat().st_mtime, reverse=True)
        for path in entries[keep:]:
            removed.append(str(path.relative_to(repo)))
            if apply:
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
    mode = "APPLY" if apply else "DRY-RUN"
    print(f"[{mode}] retention candidates: {len(removed)}")
    for path in removed:
        print(path)
    return 0


def cmd_apply(repo: Path, package_source: Path) -> int:
    package_source = package_source.resolve()
    if not package_source.is_file():
        raise PatchError(f"Patch package does not exist: {package_source}")
    manifest, _ = read_package(package_source)
    version = manifest["patch"]["version"]
    parse_version(version)
    txid = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ") + "-" + uuid.uuid4().hex[:8]
    logger = Logger(version, txid)
    verify_project(repo, manifest)

    work = repo / WORK_REL
    for directory in (work, work / "state", work / "state" / "transactions", work / "state" / "applied", work / "packages" / "incoming", work / "packages" / "applied", work / "packages" / "failed", work / "reports", work / "backups"):
        directory.mkdir(parents=True, exist_ok=True)
        os.chmod(directory, 0o700)

    with WorkLock(work / "patch.lock"):
        package_sha = sha256_file(package_source)
        check_package_duplicate(repo, work, version, package_sha)
        assert_prerequisites(repo, manifest)

        stale = []
        for tx in (work / "state" / "transactions").glob("*.json"):
            try:
                data = load_json(tx)
            except PatchError:
                continue
            if data.get("result") not in ("succeeded", "failed-rolled-back"):
                stale.append(tx.name)
        if stale:
            raise PatchError("Unresolved previous transaction state exists: " + ", ".join(sorted(stale)))

        branch = git(repo, "branch", "--show-current")
        head = git(repo, "rev-parse", "HEAD")
        status = git(repo, "status", "--porcelain=v1", "--untracked-files=all")
        if status:
            raise PatchError("Worktree must be clean before patch application.")
        if branch != manifest["git"]["baseBranch"]:
            raise PatchError(f"Patch requires branch {manifest['git']['baseBranch']!r}; current branch is {branch!r}.")
        if head != manifest["git"]["baseCommit"]:
            raise PatchError(f"Patch requires HEAD {manifest['git']['baseCommit']}; current HEAD is {head}.")

        report = work / "reports" / f"{txid}_{version}_{manifest['patch']['name']}"
        report.mkdir(parents=True)
        os.chmod(report, 0o700)
        logger.attach_report(report)
        (report / "steps").mkdir()
        (report / "package").mkdir()
        (report / "state").mkdir()
        (report / "package" / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        (report / "package" / "archive.sha256").write_text(f"{package_sha}  {package_source.name}\n", encoding="utf-8")
        logger.emit("OK", f"Project/base preflight matched {manifest['project']['repository']} at {head}.", component="PREFLIGHT")
        logger.emit("STEP", "Fetching protected base branch before any source mutation.", component="PREFLIGHT")
        run_streamed(["git", "fetch", "--prune", "origin", manifest["git"]["baseBranch"]], repo, logger, report / "steps" / "001-preflight-fetch.log", 300)
        remote_head = git(repo, "rev-parse", f"origin/{manifest['git']['baseBranch']}")
        if remote_head != head:
            raise PatchError(f"origin/{manifest['git']['baseBranch']} moved to {remote_head}; local HEAD is {head}.")
        topic = manifest["git"]["topicBranch"]
        local_branch = subprocess.run(["git", "show-ref", "--verify", "--quiet", f"refs/heads/{topic}"], cwd=repo)
        if local_branch.returncode == 0:
            raise PatchError(f"Local topic branch already exists: {topic}")
        if local_branch.returncode not in (0, 1):
            raise PatchError(f"Unable to verify local topic branch absence: {topic}")
        remote_branch = subprocess.run(["git", "ls-remote", "--exit-code", "--heads", "origin", topic], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if remote_branch.returncode == 0:
            raise PatchError(f"Remote topic branch already exists: {topic}")
        if remote_branch.returncode not in (0, 2):
            raise PatchError(f"Unable to verify remote topic branch absence: {remote_branch.stderr.decode(errors='replace').strip()}")

        environment_report(report, repo)

        state_path = work / "state" / "transactions" / f"{txid}.json"
        state: dict[str, Any] = {
            "schemaVersion": 1,
            "engineVersion": ENGINE_VERSION,
            "transactionId": txid,
            "version": version,
            "patchName": manifest["patch"]["name"],
            "startedAt": now_utc(),
            "updatedAt": now_utc(),
            "phase": "preflight",
            "result": "running",
            "repositoryRoot": str(repo),
            "baseBranch": branch,
            "baseCommit": head,
            "topicBranch": topic,
            "packageSha256": package_sha,
            "packageOriginalPath": str(package_source),
            "reportDirectory": str(report),
        }
        update_tx_state(state_path, report, state, "preflight")

        logger.emit("CHECK", "Capturing pre-application Git and filesystem evidence.", component="REPORT")
        snapshot(repo, report, "before")

        incoming = work / "packages" / "incoming" / f"{version}-{package_sha[:12]}-{package_source.name}"
        logger.emit("STEP", f"Archiving package into {incoming.relative_to(repo)} and removing the verified source copy.", component="PACKAGE")
        archived_package = copy_archive_verified(package_source, incoming, package_sha)
        state["packageArchivedPath"] = str(archived_package)
        update_tx_state(state_path, report, state, "archived")

        receipt_rel = str(APPLIED_RECEIPTS_REL / f"{version}.json")
        operation_paths = [op["path"] for op in manifest["operations"]]
        managed_paths = sorted(set(operation_paths + [receipt_rel]))
        backup = work / "backups" / txid
        backup.mkdir(parents=True)
        backup_meta = backup_paths(repo, backup, managed_paths)
        state["backupDirectory"] = str(backup)
        update_tx_state(state_path, report, state, "backed-up")

        watcher = MutationWatcher(repo, set(managed_paths), logger)
        branch_created = False
        commit_sha = ""
        pushed = False
        try:
            logger.emit("STEP", f"Creating topic branch {topic}.", component="GIT")
            run_streamed(["git", "switch", "-c", topic], repo, logger, report / "steps" / "010-branch.log", 120)
            branch_created = True
            update_tx_state(state_path, report, state, "branch-created")
            watcher.start()

            logger.emit("STEP", f"Applying {len(manifest['operations'])} declarative file operation(s).", component="APPLY")
            apply_operations(repo, archived_package, manifest)
            receipt = write_versioned_receipt(repo, manifest, txid, package_sha, head)
            logger.emit("INFO", f"Generated versioned receipt {receipt.relative_to(repo)}.", component="STATE")
            update_tx_state(state_path, report, state, "applied")
            watcher.assert_clean()

            logger.emit("CHECK", "Verifying that only package-owned repository paths changed.", component="GUARD")
            changed = git_visible_changes(repo)
            unexpected = changed - set(managed_paths)
            if unexpected:
                raise PatchError("Unexpected changed paths after apply: " + ", ".join(sorted(unexpected)))
            missing_expected = set(managed_paths) - changed
            if missing_expected:
                raise PatchError("Expected patch-owned paths are not changed: " + ", ".join(sorted(missing_expected)))

            for index, validation in enumerate(manifest["validations"], start=1):
                watcher.assert_clean()
                argv = validation["argv"]
                script = (repo / argv[0][2:]).resolve()
                try:
                    script.relative_to((repo / "scripts").resolve())
                except ValueError as exc:
                    raise PatchError(f"Validation command escapes scripts/: {argv[0]}") from exc
                if not script.is_file() or not os.access(script, os.X_OK):
                    raise PatchError(f"Validation script is missing or non-executable: {argv[0]}")
                logger.emit("CHECK", f"Validation {validation['id']} ({index}/{len(manifest['validations'])}).", component="VALIDATE")
                run_streamed(argv, repo, logger, report / "steps" / f"{100+index:03d}-{validation['id']}.log", validation["timeoutSeconds"])
                watcher.assert_clean()
            update_tx_state(state_path, report, state, "validated")

            logger.emit("CHECK", "Running git diff --check and staging only managed paths.", component="GIT")
            run_streamed(["git", "diff", "--check"], repo, logger, report / "steps" / "300-diff-check.log", 120)
            run_streamed(["git", "add", "--", *managed_paths], repo, logger, report / "steps" / "310-git-add.log", 120)
            watcher.assert_clean()
            staged_names = set(filter(None, git(repo, "diff", "--cached", "--name-only").splitlines()))
            if staged_names != set(managed_paths):
                raise PatchError(f"Staged path set mismatch. Expected {managed_paths}, got {sorted(staged_names)}")

            commit_file = report / "package" / "commit-message.txt"
            commit_file.write_text(manifest["git"]["commitMessage"].rstrip() + "\n", encoding="utf-8")
            logger.emit("STEP", "Creating signed Git commit.", component="GIT")
            run_streamed(["git", "commit", "-S", "-F", str(commit_file)], repo, logger, report / "steps" / "320-commit.log", 300)
            commit_sha = git(repo, "rev-parse", "HEAD")
            signature = git(repo, "log", "-1", "--format=%G?")
            if signature != "G":
                raise PatchError(f"Commit signature verification failed: %G?={signature!r}")
            state["commit"] = commit_sha
            update_tx_state(state_path, report, state, "committed")

            logger.emit("CHECK", "Running final repository validation on committed state.", component="VALIDATE")
            run_streamed(["./scripts/validate-repository.sh"], repo, logger, report / "steps" / "400-final-repository.log", 1800)
            if git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
                raise PatchError("Final validation left the worktree dirty.")

            if manifest["git"]["push"]:
                logger.emit("STEP", f"Pushing {topic} to origin.", component="GIT")
                run_streamed(["git", "push", "-u", "origin", topic], repo, logger, report / "steps" / "410-push.log", 600)
                pushed = True
                update_tx_state(state_path, report, state, "pushed")

            watcher.stop()
            snapshot(repo, report, "after")
            state.update({"result": "succeeded", "finishedAt": now_utc(), "phase": "succeeded"})
            atomic_write_json(state_path, state)
            local_receipt = {
                "schemaVersion": 1,
                "version": version,
                "name": manifest["patch"]["name"],
                "transactionId": txid,
                "packageSha256": package_sha,
                "commit": commit_sha,
                "branch": topic,
                "appliedAt": now_utc(),
                "reportDirectory": str(report),
            }
            atomic_write_json(work / "state" / "applied" / f"{version}.json", local_receipt)
            applied_dir = work / "packages" / "applied" / version
            applied_dir.mkdir(parents=True, exist_ok=True)
            final_package = applied_dir / archived_package.name
            os.replace(archived_package, final_package)
            state["packageArchivedPath"] = str(final_package)
            atomic_write_json(state_path, state)
            write_report_summary(report, state, manifest)
            logger.emit("OK", f"Patch {version} completed successfully. Report: {report}", component="RESULT")
            logger.emit("INFO", f"Branch: {topic} | Commit: {commit_sha}", component="RESULT")
            return 0
        except BaseException as exc:
            try:
                watcher.stop()
            except Exception:
                pass
            error_text = str(exc) or exc.__class__.__name__
            logger.emit("ERROR", f"Patch failed: {error_text}", component="RESULT")
            rollback_error = None
            try:
                logger.emit("STEP", "Restoring package-owned paths and original Git state.", component="ROLLBACK")
                if pushed and commit_sha:
                    remote = subprocess.run(["git", "ls-remote", "--heads", "origin", topic], cwd=repo, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    remote_sha = remote.stdout.split()[0] if remote.returncode == 0 and remote.stdout.strip() else ""
                    if remote_sha == commit_sha:
                        subprocess.run(["git", "push", "origin", "--delete", topic], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                if git(repo, "branch", "--show-current") == topic:
                    subprocess.run(["git", "reset", "--hard", head], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                    subprocess.run(["git", "switch", branch], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                restore_backup(repo, backup, backup_meta)
                subprocess.run(["git", "reset", "--hard", head], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                if branch_created:
                    subprocess.run(["git", "branch", "-D", topic], cwd=repo, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
                if git(repo, "status", "--porcelain=v1", "--untracked-files=all"):
                    raise PatchError("Rollback completed but the Git-visible worktree is not clean.")
                logger.emit("OK", "Rollback restored the pre-application Git-visible state.", component="ROLLBACK")
            except Exception as rb_exc:
                rollback_error = str(rb_exc)
                logger.emit("ERROR", f"Rollback failed: {rollback_error}", component="ROLLBACK")
            try:
                failed_dir = work / "packages" / "failed" / version / txid
                failed_dir.mkdir(parents=True, exist_ok=True)
                if archived_package.exists():
                    os.replace(archived_package, failed_dir / archived_package.name)
            except OSError:
                pass
            try:
                snapshot(repo, report, "rollback")
            except Exception:
                pass
            state.update({
                "result": "failed-rolled-back" if rollback_error is None else "rollback-failed",
                "finishedAt": now_utc(),
                "phase": "failed",
                "error": error_text,
                "rollbackError": rollback_error,
            })
            atomic_write_json(state_path, state)
            write_report_summary(report, state, manifest)
            raise
        finally:
            logger.close()


def main() -> int:
    os.umask(0o077)
    parser = argparse.ArgumentParser(description="Nexali durable patch engine")
    sub = parser.add_subparsers(dest="command", required=True)
    apply_parser = sub.add_parser("apply")
    apply_parser.add_argument("--package", required=True)
    sub.add_parser("status")
    cleanup = sub.add_parser("cleanup")
    cleanup.add_argument("--apply", action="store_true")
    sub.add_parser("self-test")
    args = parser.parse_args()

    if args.command == "self-test":
        return cmd_self_test()
    repo = find_repo_from_cwd()
    if args.command == "status":
        return cmd_status(repo)
    if args.command == "cleanup":
        return cmd_cleanup(repo, args.apply)
    if args.command == "apply":
        return cmd_apply(repo, Path(args.package))
    return 2


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except PatchError as exc:
        print(f"[NEXALI][PATCH][ERROR] {exc}", file=sys.stderr)
        raise SystemExit(1)
