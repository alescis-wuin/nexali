#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import re
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

SCHEMA_VERSION = 1
VERSION_RE = re.compile(r"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$")
HEX64_RE = re.compile(r"^[0-9a-f]{64}$")
PROJECT_ID_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
BRANCH_RE = re.compile(r"^(feature|fix|refactor|test|docs|security|perf|build|ci|chore|release)/[a-z0-9]+(?:-[a-z0-9]+)*$")


class PatchError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def atomic_write_bytes(path: Path, data: bytes, mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    tmp = Path(tmp_name)
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
            fh.flush()
            os.fsync(fh.fileno())
        os.chmod(tmp, mode)
        os.replace(tmp, path)
        try:
            dir_fd = os.open(path.parent, os.O_RDONLY)
            try:
                os.fsync(dir_fd)
            finally:
                os.close(dir_fd)
        except OSError:
            pass
    finally:
        if tmp.exists():
            tmp.unlink()


def atomic_write_json(path: Path, value: Any, mode: int = 0o600) -> None:
    data = (json.dumps(value, indent=2, sort_keys=True, ensure_ascii=False) + "\n").encode("utf-8")
    atomic_write_bytes(path, data, mode=mode)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PatchError(f"Unable to read valid JSON from {path}: {exc}") from exc


def parse_version(value: str) -> tuple[int, int, int]:
    match = VERSION_RE.fullmatch(value)
    if not match:
        raise PatchError(f"Invalid patch version '{value}'. Expected X.Y.Z with non-negative integers and no leading zeroes.")
    return tuple(int(part) for part in match.groups())


def safe_rel_path(value: str) -> PurePosixPath:
    if not value or "\x00" in value or "\\" in value:
        raise PatchError(f"Unsafe repository path: {value!r}")
    path = PurePosixPath(value)
    if path.is_absolute() or any(part in ("", ".", "..") for part in path.parts):
        raise PatchError(f"Unsafe repository path: {value!r}")
    if path.parts[0] in (".git", ".work"):
        raise PatchError(f"Patch operations may not target {path.parts[0]}: {value}")
    return path


def ensure_hex64(value: str, field: str) -> None:
    if not HEX64_RE.fullmatch(value):
        raise PatchError(f"{field} must be a lowercase SHA-256 hex digest.")


def validate_manifest(manifest: dict[str, Any]) -> dict[str, Any]:
    if manifest.get("schemaVersion") != SCHEMA_VERSION:
        raise PatchError(f"Unsupported schemaVersion: {manifest.get('schemaVersion')!r}")

    project = manifest.get("project")
    patch = manifest.get("patch")
    git = manifest.get("git")
    operations = manifest.get("operations")
    validations = manifest.get("validations")
    if not isinstance(project, dict) or not isinstance(patch, dict) or not isinstance(git, dict):
        raise PatchError("Manifest must contain project, patch, and git objects.")
    if not isinstance(operations, list) or not operations:
        raise PatchError("Manifest operations must be a non-empty array.")
    if not isinstance(validations, list) or not validations:
        raise PatchError("Manifest validations must be a non-empty array.")

    project_id = project.get("id")
    project_guid = project.get("guid")
    repository = project.get("repository")
    if not isinstance(project_id, str) or not PROJECT_ID_RE.fullmatch(project_id):
        raise PatchError("project.id is invalid.")
    if not isinstance(project_guid, str) or not project_guid:
        raise PatchError("project.guid is required.")
    if not isinstance(repository, str) or repository.count("/") != 1:
        raise PatchError("project.repository must be owner/name.")

    version = patch.get("version")
    if not isinstance(version, str):
        raise PatchError("patch.version is required.")
    major, step, fix = parse_version(version)
    if patch.get("major") != major or patch.get("step") != step or patch.get("fix") != fix:
        raise PatchError("patch.major/step/fix must match patch.version X.Y.Z.")
    name = patch.get("name")
    if not isinstance(name, str) or not PROJECT_ID_RE.fullmatch(name):
        raise PatchError("patch.name must be lowercase kebab-case.")
    requires = patch.get("requires", [])
    if not isinstance(requires, list) or any(not isinstance(v, str) for v in requires):
        raise PatchError("patch.requires must be an array of versions.")
    for requirement in requires:
        parse_version(requirement)

    base_branch = git.get("baseBranch")
    topic_branch = git.get("topicBranch")
    base_commit = git.get("baseCommit")
    commit_message = git.get("commitMessage")
    push = git.get("push")
    if base_branch not in ("develop", "testing", "main"):
        raise PatchError("git.baseBranch must be develop, testing, or main.")
    if not isinstance(topic_branch, str) or not BRANCH_RE.fullmatch(topic_branch):
        raise PatchError("git.topicBranch violates Nexali branch naming policy.")
    if not isinstance(base_commit, str) or not re.fullmatch(r"[0-9a-f]{40}", base_commit):
        raise PatchError("git.baseCommit must be a full lowercase Git SHA-1.")
    if not isinstance(commit_message, str) or "\n\nDescription:\n" not in commit_message or "\n\nChanges:\n" not in commit_message:
        raise PatchError("git.commitMessage must follow the Nexali structured commit format.")
    if not isinstance(push, bool):
        raise PatchError("git.push must be a boolean.")

    seen_paths: set[str] = set()
    for index, operation in enumerate(operations):
        if not isinstance(operation, dict):
            raise PatchError(f"operations[{index}] must be an object.")
        op_type = operation.get("type")
        if op_type not in ("add", "replace", "delete"):
            raise PatchError(f"operations[{index}].type is invalid.")
        path = str(safe_rel_path(operation.get("path", "")))
        if path in seen_paths:
            raise PatchError(f"Duplicate operation path: {path}")
        seen_paths.add(path)
        if op_type in ("add", "replace"):
            source = operation.get("source")
            if not isinstance(source, str) or not source.startswith("payload/"):
                raise PatchError(f"operations[{index}].source must begin with payload/.")
            safe_rel_path(source)
            after = operation.get("afterSha256")
            if not isinstance(after, str):
                raise PatchError(f"operations[{index}].afterSha256 is required.")
            ensure_hex64(after, f"operations[{index}].afterSha256")
            mode = operation.get("mode", "0644")
            if mode not in ("0644", "0755"):
                raise PatchError(f"operations[{index}].mode must be 0644 or 0755.")
        if op_type in ("replace", "delete"):
            before = operation.get("beforeSha256")
            if not isinstance(before, str):
                raise PatchError(f"operations[{index}].beforeSha256 is required.")
            ensure_hex64(before, f"operations[{index}].beforeSha256")

    for index, validation in enumerate(validations):
        if not isinstance(validation, dict):
            raise PatchError(f"validations[{index}] must be an object.")
        validation_id = validation.get("id")
        argv = validation.get("argv")
        timeout = validation.get("timeoutSeconds")
        if not isinstance(validation_id, str) or not PROJECT_ID_RE.fullmatch(validation_id):
            raise PatchError(f"validations[{index}].id must be kebab-case.")
        if not isinstance(argv, list) or not argv or any(not isinstance(arg, str) or not arg for arg in argv):
            raise PatchError(f"validations[{index}].argv must be a non-empty string array.")
        first = argv[0]
        if not first.startswith("./scripts/"):
            raise PatchError(f"validations[{index}] must execute a versioned repository script under ./scripts/.")
        safe_rel_path(first[2:])
        if not isinstance(timeout, int) or not 1 <= timeout <= 7200:
            raise PatchError(f"validations[{index}].timeoutSeconds must be between 1 and 7200.")

    return manifest


def normalize_github_origin(url: str) -> str | None:
    value = url.strip()
    patterns = (
        r"^git@github\.com:(?P<repo>[^/]+/[^/]+?)(?:\.git)?$",
        r"^ssh://git@github\.com/(?P<repo>[^/]+/[^/]+?)(?:\.git)?$",
        r"^https://github\.com/(?P<repo>[^/]+/[^/]+?)(?:\.git)?/?$",
    )
    for pattern in patterns:
        match = re.match(pattern, value)
        if match:
            return match.group("repo").removesuffix(".git")
    return None
