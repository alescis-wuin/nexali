# Durable patch workflow

Nexali patch packages use a repository-owned engine rather than reimplementing transaction logic in every ZIP.

## One-command contract

A standard package is launched with one command:

```bash
bash "$HOME/Téléchargements/<package>.zip"
```

The command may be invoked from the repository root or any subdirectory of the target repository. It is rejected when the current directory is outside the target Git worktree or when the project identity/origin does not match the package manifest. The launcher runs as a child Bash process and never exits or changes the caller's interactive shell.

## Patch version

Patch versions use exactly `X.Y.Z`:

- `X`: major project patch or phase.
- `Y`: ordered step within the major patch.
- `Z`: corrective revision for that step.

Examples: `1.9.0` is the initial Phase 1 / Step 9 patch; `1.9.1` is its first corrective revision. Leading zeroes and extra components are forbidden.

The durable engine enforces two independent duplicate guards:

1. A versioned receipt under `eng/patch/applied/<version>.json`, which survives clones and merges.
2. A local receipt under `.work/patch-engine/state/applied/`, which prevents a second local application even before the topic branch is merged.

The exact archive SHA-256 is stored in receipts. Reusing the same archive under another version is also rejected locally.

## Project identity and current-directory safety

`eng/patch/project.json` defines the stable project identity. A package must match:

- project ID and GUID;
- GitHub `owner/name`;
- integration/base branch;
- exact base commit declared in the package.

Before source mutation, the engine resolves the repository with `git rev-parse --show-toplevel`, requires the current directory to be inside that worktree, validates `origin`, requires a clean worktree, fetches the protected base, and verifies that local and remote base SHAs still match.

## Package format

A standard package contains:

```text
patch/
├── manifest.json
├── SHA256SUMS
└── payload/
    └── ... exact postimages ...
```

`manifest.json` declares:

- project identity;
- patch version and prerequisites;
- exact base commit and topic branch;
- structured signed commit message;
- declarative `add`, `replace`, or `delete` operations;
- exact preimage/postimage SHA-256 values;
- repository-owned validation commands under `./scripts/`;
- whether the validated topic branch is pushed.

Package ZIP members, repository paths and targets are checked for traversal and symlinks. Package-provided arbitrary shell hooks are not part of schema v1.

## Durable local workspace

Operational data lives in ignored `.work/patch-engine/`:

```text
.work/patch-engine/
├── patch.lock
├── packages/
│   ├── incoming/
│   ├── applied/<version>/
│   └── failed/<version>/<transaction>/
├── reports/<transaction>_<version>_<name>/
├── backups/<transaction>/
└── state/
    ├── applied/
    └── transactions/
```

When a package is launched from `~/Téléchargements`, the engine copies it into `.work`, verifies the copy's SHA-256, atomically promotes the verified copy inside `.work`, then removes the source. This is deliberately safer than relying on a cross-filesystem `mv`.

## Transaction and rollback

Each application uses an exclusive advisory file lock and a transaction state machine. State files are written through temporary files followed by atomic replacement on the same filesystem.

The engine:

1. validates project/package/base state;
2. acquires the repository patch lock;
3. creates the report and archives the package;
4. backs up every owned path;
5. creates the topic branch;
6. applies declarative file operations;
7. creates the versioned receipt;
8. rejects unexpected Git-visible changes outside package-owned paths;
9. runs declared validation gates with timeouts;
10. runs `git diff --check`;
11. stages only package-owned paths;
12. creates and verifies a GPG-signed commit;
13. re-runs the full repository validation;
14. pushes only after every gate succeeds;
15. stores the successful local receipt and final report.

Ordinary failures trigger rollback of package-owned files and the original Git branch/HEAD. A failed package and its report are retained under `.work` for diagnosis.

## Logging and reports

Console messages use the prefix:

```text
[local ISO-8601 time][NEXALI][PATCH X.Y.Z][component][level][TX id] message
```

Colors are enabled only for a capable TTY and are disabled when `NO_COLOR` is set. Every report includes:

- `console.log` and `console.ansi.log`;
- `events.jsonl` with structured events;
- raw output per validation under `steps/`;
- project/toolchain information under `environment/`;
- package manifest and SHA-256 evidence;
- before/after/rollback Git evidence;
- `tree.txt`;
- tracked file sizes, modes, UTC mtimes and SHA-256 checksums;
- `git status`, logs, branches, remotes, staged/unstaged diffs and HEAD details;
- transaction state snapshots and final Markdown/JSON summaries.

Full environment dumps are intentionally not collected. Only an explicit safe environment whitelist is recorded.

## Package creation

The repository tool:

```bash
python3 scripts/patch/build-package.py \
  --package-dir /path/to/package-source \
  --output /path/to/nexali-X.Y.Z-name.zip
```

validates the manifest/postimages, creates deterministic ZIP entries and prepends the standard Bash launcher. Future AI-generated packages should use this builder or produce the same schema exactly.

## State and retention

Inspect state with:

```bash
./scripts/patch/patchctl.sh status
```

Preview rotation candidates without deleting anything:

```bash
./scripts/patch/patchctl.sh cleanup
```

Apply the configured retention limits explicitly:

```bash
./scripts/patch/patchctl.sh cleanup --apply
```

Retention limits are versioned in `eng/patch/project.json`. Automatic destructive cleanup is intentionally not enabled.
