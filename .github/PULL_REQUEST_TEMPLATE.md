## Purpose

<!-- What problem does this PR solve? -->

## Gitflow

- Source branch: `<!-- <type>/<name> | develop | testing -->`
- Target branch: `<!-- develop | testing | main -->`

Expected promotion path: `<type>/<name> -> develop -> testing -> main`.

## Changes

<!-- Summarize the important changes. -->

## Testing

<!-- List automated/manual validation performed. -->

## Security impact

<!-- None, or explain security-sensitive changes. -->

## Accessibility impact

<!-- None, or explain accessibility validation. -->

## Architecture impact

<!-- None, or link the ADR/rule change. -->

## Migration impact

<!-- None, or document migration/rollback implications. -->

## Checklist

- [ ] Source and target branches respect the Nexali Gitflow.
- [ ] Required CI checks (`PR source chain`, `Repository gate`) pass.
- [ ] Branch name matches `<type>/<name>` when this is a topic branch.
- [ ] Commit messages follow the required header/body/footer convention.
- [ ] Commits are signed.
- [ ] Tests were added or updated where relevant.
- [ ] Architecture boundaries are respected.
- [ ] No secrets or real user data were added.
- [ ] Logging/diagnostics contain no sensitive data.
- [ ] Accessibility was considered for UI changes.
- [ ] Documentation was updated where needed.
- [ ] Breaking changes are explicitly documented.
