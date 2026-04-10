# Release

Package update and release workflow for Quantroot.

## Prerequisites

- All tests passing (`make test-demo`)
- No uncommitted changes
- On the release branch

## Preflight

```bash
make check
make test-demo
git status  # should be clean
```

## Dependency Graph

{{Document the order in which packages/services must be updated.}}

## Per-Package Release Procedure

{{Document the release steps for each package/submodule.}}

## Service Updates

{{Document how to update service images after a package release.}}

## E2E Validation

After updating services, run the full E2E suite:

```bash
make test-demo
```

## Finalization

1. Update `CHANGELOG.md` with the new version
2. Tag the release: `git tag -a vX.Y.Z -m "Release vX.Y.Z"`
3. Push: `git push origin main --tags`
