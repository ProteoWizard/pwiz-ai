# Release Cycle Guide

Quick reference for understanding where we are in the Skyline release cycle and what that means for daily work.

For detailed release procedures, see `ai/docs/release-guide.md`.

## Current State

**Phase**: POST-RELEASE PATCH (Major release shipped)
**Release Branch**: `Skyline/skyline_26_1`
**Released Version**: Skyline 26.1.0.057 (Feb 26, 2026)
**Master Version**: 26.1.1.xxx (daily builds)
**Branch Created**: 2026-01-04

## Release Cycle Phases

### 1. Open Development (Normal)

**When**: After a major release, before next FEATURE COMPLETE

- Master is the primary development branch
- No active release branch (or release branch only for emergency patches)
- PRs merge freely to master
- Nightly tests run on master only
- No cherry-pick considerations

**Cherry-pick policy**: N/A - no active release branch

### 2. FEATURE COMPLETE / Release Candidate

**When**: Release branch created, preparing for major release

- **Release branch** receives bug fixes only (no new features)
- **Master** continues development for next release
- Both branches run nightly tests
- PRs may need cherry-picking to release branch

**Cherry-pick policy**:
- Bug fixes: Add "Cherry pick to release" label
- New features: Master only (no label)
- Refactoring: Usually master only unless it fixes a bug

**Test interpretation**:
- Same failure on both branches early in this phase = likely same code (branches just diverged)
- Same failure later = potentially systemic issue or cherry-picked bug

**Current release branch**: `Skyline/skyline_26_1`

### 3. Post-Release Patch Mode ← CURRENT PHASE

**When**: Major release shipped, critical fixes may be needed

- Release branch used only for **critical** bug fixes (crashes, data loss, security)
- Master continues normal development — most PRs go here only
- Cherry-picks are **rare** and require justification
- The release branch diverges increasingly from master over time

**Cherry-pick policy**:
- **Default is NO cherry-pick** — do not add the label unless criteria below are met
- Only cherry-pick if ALL of these are true:
  1. The bug affects **released users** (not just daily/master users)
  2. The bug is **critical** (crash, data loss, corruption, security, or blocks a common workflow)
  3. The **code being fixed exists on the release branch** — verify with:
     ```bash
     git log Skyline/skyline_26_1 -- path/to/file.cs | head -3
     ```
     If the file or code path was added after the release branch was created, it is
     master-only code and cherry-picking makes no sense
- New features, refactoring, and non-critical bugs: **master only** (no label)
- When in doubt, do NOT add the label — ask the team lead

### 4. Release Branch Dormant

**When**: Release is stable, no patches expected

- Release branch exists but rarely touched
- All development on master
- Effectively same as Open Development

## Quick Decision Tree: Should I Cherry-Pick?

### During FEATURE COMPLETE (pre-release)
```
Is this a bug fix?
├── No (feature/refactor) → Master only
└── Yes → Add "Cherry pick to release" label
    └── Is it critical/blocking?
        ├── Yes → Consider direct commit to release branch
        └── No → Label is sufficient, auto-cherry-pick on merge
```

### During POST-RELEASE PATCH (current phase)
```
Is this a bug fix?
├── No → Master only (no label)
└── Yes → Is it critical (crash, data loss, security, blocks common workflow)?
    ├── No → Master only (no label)
    └── Yes → Does the affected code exist on the release branch?
        ├── No (code was added after branch point) → Master only (no label)
        └── Yes → Add "Cherry pick to release" label
```

**Important**: As time passes after a major release, master and the release branch
diverge significantly. Code added to master after the branch point does NOT exist
on the release branch. Always verify before labeling.

## Cherry-Pick Label Gotchas

The "Cherry pick to release" label triggers an automatic cherry-pick when a PR is merged. Two common issues can cause this to fail:

### 1. Deleting the PR branch too early

**Problem**: If you delete the source branch immediately after merging, the cherry-pick bot may not have time to create the cherry-pick PR.

**Solution**: Wait for the cherry-pick PR to be created before deleting the branch, or be prepared to manually cherry-pick if needed:
```bash
git checkout -b Skyline/work/YYYYMMDD_feature_release origin/Skyline/skyline_26_1
git cherry-pick <squash-merge-commit-hash>
git push -u origin Skyline/work/YYYYMMDD_feature_release
gh pr create --base Skyline/skyline_26_1
```

### 2. Merge commits in the PR history

**Problem**: If you update your branch with `git merge master` instead of rebasing, the merge commits interfere with the squash-and-merge process, causing the cherry-pick to fail or produce unexpected results.

**Solution**: Always update your branch with rebase:
```bash
git pull --rebase origin master
```

Or use the `/rebase` comment on the PR before squash-and-merge to have GitHub rebase your commits automatically.

## Nightly Test Interpretation

### When branches just diverged (early FEATURE COMPLETE)

- Master and release branch have nearly identical code
- Same failure on both = single issue, not "systemic across branches"
- Focus on fixing once, cherry-pick will sync both

### When branches have diverged significantly

- Same failure on both = may indicate:
  - Long-standing issue
  - External dependency problem (Koina, Panorama, etc.)
  - Test infrastructure issue
- Different failures = branch-specific changes

### Missing computers

- Check if computer is expected on that branch
- Some computers only run master, others run release branch
- BOSS-PC, SKYLINE-DEV1 may have configuration issues

## Version Numbering

### Format: `YY.N.B.DDD`

| Component | Name | Values | Description |
|-----------|------|--------|-------------|
| `YY` | Year | 24, 25, 26... | Year of release (also base year for day calculation) |
| `N` | Ordinal | 0, 1, 2... | Release number within year (0 = first/unreleased, 1 = first official) |
| `B` | Branch | 0, 1, 9 | Build type: 0=release (Skyline.exe), 1=daily (Skyline-daily.exe), 9=feature complete (Skyline-daily.exe) |
| `DDD` | Day | 001-365 | Zero-padded day of year from git commit date |

### Version Examples

| Version | Meaning |
|---------|---------|
| `26.1.1.004` | 2026, release 1, daily build, day 4 (Jan 4) |
| `26.0.9.004` | 2026, release 0, feature complete, day 4 |
| `26.1.0.045` | 2026, release 1, official release, day 45 (Feb 14) |
| `25.1.1.369` | 2025, release 1, daily, day 369 (crosses into 2026 = 365 + day 4) |

### Day-of-Year Calculation

Day-of-year is calculated from the **git commit date** (not build date), enabling reproducible builds.

```
DDD = (year_2digit - SKYLINE_YEAR) * 365 + day_of_year(commit_date)
```

Example: Jan 4, 2026 with SKYLINE_YEAR=26 → DDD = (26-26)*365 + 4 = 004

### Quick Reference

| Phase | Version Pattern | Example | Product | skyline.ms Container |
|-------|-----------------|---------|---------|---------------------|
| Daily (master) | YY.N.1.DDD | 26.1.1.007 | Skyline-daily.exe | `/home/software/Skyline/daily` |
| FEATURE COMPLETE | YY.0.9.DDD | 26.0.9.007 | Skyline-daily.exe | `/home/software/Skyline/daily` |
| Release | YY.N.0.DDD | 26.1.0.045 | Skyline.exe | `/home/software/Skyline` |

Both daily and feature complete builds ship as **Skyline-daily.exe**. Only official releases ship as **Skyline.exe**. Release announcements are posted to the announcements board in the corresponding container (see [ai/docs/mcp/announcements.md](mcp/announcements.md)).

## Git Tags

Every published release is tagged. Tags let you navigate from a version number to the exact source code.

### Tag Format

| Release Type | Tag Format | Example |
|--------------|------------|---------|
| Daily (beta) | `Skyline-daily-YY.N.1.DDD` | `Skyline-daily-25.1.1.147` |
| Feature Complete | `Skyline-daily-YY.N.9.DDD` | `Skyline-daily-26.0.9.004` |
| Official Release | `Skyline-YY.N.0.DDD` | `Skyline-26.1.0.045` |

### Finding Tags and Commits

```bash
# List all tags for a release series
git tag -l "Skyline-daily-26*"

# Show what commit a tag points to
git show Skyline-daily-26.0.9.004 --no-patch

# Commits between two releases
git log Skyline-daily-26.0.9.004..Skyline-daily-26.0.9.021 --oneline

# Check if a specific commit is in a release
git branch --contains <commit-hash>
git tag --contains <commit-hash>
```

### Investigating Whether a Bug Is Fixed

When an exception report or test failure occurs on a specific version:

1. **Parse the version** to determine branch and approximate date:
   - `B=1` → master (daily), `B=9` → release branch (feature complete), `B=0` → release
2. **Find the tag**: `git tag -l "Skyline-daily-YY.N.B.*"` or `git tag -l "Skyline-YY.N.0.*"`
3. **Check if the fix is in a later tag**:
   ```bash
   # Is the fix commit included in the user's version?
   git merge-base --is-ancestor <fix-commit> <release-tag>
   ```
4. **Check which branch has the fix**:
   ```bash
   git log --oneline master -- path/to/file.cs | head -5
   git log --oneline Skyline/skyline_26_1 -- path/to/file.cs | head -5
   ```
5. **Check if a PR was cherry-picked** to the release branch:
   ```bash
   gh pr list --state merged --base Skyline/skyline_26_1 --search "cherry pick"
   ```

### Release Folder Locations

| Branch | Local Folder (relative to project root) | Purpose |
|--------|-------------|---------|
| `master` | `pwiz` | Ongoing development |
| `Skyline/skyline_26_1` | `skyline_26_1` | Current release branch |
| `Skyline/skyline_25_1` | `skyline_25_1` | Previous release (reference) |

## Updating This Document

Update the "Current State" section when:
- Creating a new release branch (entering FEATURE COMPLETE)
- Shipping a major release (entering Post-Release Patch)
- Deciding release branch is dormant (entering Open Development)

For detailed release procedures, see `ai/docs/release-guide.md`.
