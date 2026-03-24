---
argument-hint: <type> [folder]
description: Guided release workflow (daily, complete, rc, major, patch)
---

# Release Workflow: $ARGUMENTS

Load the release-management skill, then read **ai/docs/release-guide.md** for full instructions.

## Arguments

- **type** (required): One of `daily`, `complete`, `rc`, `major`, `patch`
- **folder** (optional): Release subfolder name in the project root (e.g., `daily`, `skyline_26_1`)

If no folder is specified, infer from type:
- `daily` → `daily` subfolder
- `complete`, `rc`, `major`, `patch` → `skyline_YY_N` subfolder (check what exists)

## Active Release Folders

| Folder | Branch | Purpose |
|--------|--------|---------|
| `daily` | `master` | Skyline-daily builds |
| `skyline_26_1` | `Skyline/skyline_26_1` | Skyline patches (current stable) |

## Release Type Quick Reference

| Type | Version Format | Branch | Guide Section |
|------|----------------|--------|---------------|
| `daily` | `YY.N.1.DDD` | `master` | "Skyline-daily (beta)" |
| `complete` | `YY.N.9.DDD` | `Skyline/skyline_YY_N` | "Skyline-daily (FEATURE COMPLETE)" |
| `rc` | `YY.N.9.DDD` | `Skyline/skyline_YY_N` | Same as complete, on existing branch |
| `major` | `YY.N.0.DDD` | `Skyline/skyline_YY_N` | "Skyline (release)" |
| `patch` | `YY.N.0.DDD` | `Skyline/skyline_YY_N` | "Skyline (patch)" |

## Workflow

1. **Load skill**: Load the `release-management` skill
2. **Read guide**: Read `ai/docs/release-guide.md` — find the section matching the release type
3. **Verify folder**: Confirm the release folder exists and is on the correct branch
   ```bash
   ls <project-root>/<folder>
   git -C <project-root>/<folder> branch --show-current
   ```
4. **Walk through steps**: Follow the guide section step-by-step, confirming with the developer before each action that modifies state (commits, tags, publishes, wiki updates, announcements)

## Key Differences by Type

### daily
- Build and publish from the `daily` subfolder (master branch)
- Generate release notes from commits since last tag
- Post to `/home/software/Skyline/daily` container
- MailChimp to beta list only (~5,000 users)

### complete
- Creates a new release branch `Skyline/skyline_YY_N`
- Sets up the release folder from scratch
- 16-step workflow including TeamCity, translations, tutorials
- Notify dev team immediately after branch creation

### rc
- Uses existing release branch and folder
- Same publish workflow as `complete` (steps 7-16)
- No branch creation, no TeamCity changes, no translation CSV generation

### major
- 8-phase workflow transforming Skyline-daily into Skyline
- Phase 1 changes cherry-pick to master; Phase 2 stays on release branch
- Different publish paths than daily (see Publish Paths Reference in guide)
- Post to `/home/software/Skyline/releases` container
- MailChimp to full Skyline list (~23,500 users)
- Same-day first Skyline-daily from master afterward

### patch
- Cherry-pick fixes from master to release branch
- Same publish paths as major release
- Only DDD changes in version — same ORDINAL and BRANCH
- Higher bar: critical bug fixes only

## Related

- [ai/docs/release-guide.md](../../ai/docs/release-guide.md) — Full release documentation
- `/pw-cptorelease` — Cherry-pick a PR to the release branch
