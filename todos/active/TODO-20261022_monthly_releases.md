# Monthly pinned releases of Core Windows x86_64 (bt83) and a release archive on the website

## Branch Information
- **Branch**: `Skyline/work/20261022_monthly_releases`
- **Base**: `master`
- **Created**: 2026-10-22
- **Status**: In Progress
- **GitHub Issue**: [#4899](https://github.com/ProteoWizard/pwiz/issues/4899)
- **Module**: `pwiz`
- **PR**: [#4905](https://github.com/ProteoWizard/pwiz/pull/4905) (merged 2026-10-23), follow-up [#4910](https://github.com/ProteoWizard/pwiz/pull/4910) (tags `release-[daily-]YYYY-MM-DD-sha` from the installer version; the 9 existing tags renamed 2026-10-23 - do not run the publish job on master until #4910 merges, then run it once to republish before merging web#28); seed PR [#4900](https://github.com/ProteoWizard/pwiz/pull/4900) (closed, never merged); website [ProteoWizard/web#28](https://github.com/ProteoWizard/web/pull/28)

## Objective

Publish a monthly ProteoWizard release from Core Windows x86_64 (bt83). When a new month starts, the last successful default-branch bt83 build of the previous month is pinned and tagged `release-YYYY-MM` in TeamCity. The pwiz website (ProteoWizard/web) gets an archive page for browsing and downloading past monthly releases. To seed the archive, the last build of each of Feb-Sep 2026 is rebuilt and pinned.

Out of scope: Linux (bt17) and Bumbershoot artifacts, and manual mid-month pins. The seed builds only need to produce the Windows installer.

The issue body holds the full technical detail: how the website resolves downloads, the two installer generations, retention, the seed commit table and the seeding design.

## Tasks

- [x] Seed PR #4900 (draft, never merged): `bt83.xml` from `2deb47a782` + `seed.commit` parameter + first step that fetches it by SHA and checks it out as `master` + artifacts limited to `build-nt-x86/*.msi` and `build-nt-x86/VERSION`
- [x] Trial seed build for 2026-09 (`10aac2d`): build 4230560, `3.0.26272.10aac2d9`, 308/308 tests, pinned + tagged `release-2026-09`
- [x] Remaining 7 seed builds; pin + tag each `release-YYYY-MM` with the seed commit in the pin comment
- [x] Monthly pin job written (uncommitted): `scripts/misc/publish_monthly_release.py` + `.teamcity/ProteoWizard/buildTypes/ProteoWizard_PublishMonthlyRelease.xml` (cron 06:00 server time on the 1st; pins/tags the previous month, writes and SFTPs `bt83-monthly.xml` + `bt83-archive.json`; dry run off the default branch)
- [x] (2026-10-23: first run 403'd - the server's customized Project developer role lacks pin_unpin_build/tag_build; after the user fixed pwiz-commit's permissions the rerun released build 4232279 as release-2026-10-23 and both files went live) After merge: run it manually with "Release the latest build now" (`--latest`; the mid-month October release, user decision 2026-10-22), confirm `pwiz-commit` can pin, and check both files at https://proteowizard.sourceforge.io/releases/
- [x] Archive metadata covers every pinned SUCCESS bt83 build tagged `release-YYYY-MM` on any branch
- [ ] Website in ProteoWizard/web (uncommitted, branch `release-channels` in `C:\dev\pwiz-web-help`): Monthly/Beta channel selector for the Windows installers + archive dropdown with a license-gated Download button. Merge only after the pin job publishes `releases/bt83-monthly.xml` and `releases/bt83-archive.json`
- [ ] Commit-date versioning in `scripts/installer/build.ps1` (and `build-linux.sh`)

## Seed commits

| Month | Original build id | Commit |
|---|---|---|
| 2026-09 | 4193616 | `10aac2d94868c4dc83f9ae5ac349a6970dc976af` |
| 2026-08 | 4155594 | `99609d5bc0aceffc3650a2724364aa1f18e17795` |
| 2026-07 | 4115775 | `72e04015235cd51ccab9e526b4d4136718065dc8` |
| 2026-06 | 4071095 | `1c640eff6669097d9acc73f93e14b730e3548f7a` |
| 2026-05 | 4022388 | `e7e989cc7d7c47c4af106f1d43357e5fe45cb82c` |
| 2026-04 | 3964051 | `bb3c999a56e076624d6e4a5438808e070f1a0116` |
| 2026-03 | 3914594 | `f128208ebda9b9acfe52f6ce1138b866c319c16d` |
| 2026-02 | 3869043 | `7b1a2a7bcbf48306c9ef292e940f4e0829a64ab6` |

## Progress Log

### 2026-10-22 - Session Start

Researched and filed #4899. Key findings:
* `releases/bt83.xml` is overwritten per default-branch build by the `ProteoWizard_UploadArtifactMetadataToSourceForge` meta-runner; no history.
* bt83 artifact retention is ~2 weeks (artifacts back to 2026-10-08 only); nothing pinned.
* All 8 seed months are C++-tree builds; the C++ Jamroot stamps the date and SHA from `HEAD` (commit date since `cee2c514d0`), so a build with `HEAD` detached at the seed commit is stamped correctly without clock changes.
* bt83 settings only entered VCS at `2deb47a782` (C++-era export); since then only `bt83.xml` changed among bt83's settings, so a PR restoring it runs the C++ pipeline under `PREFER_VCS`.

### 2026-10-22 - Seed PR and the September trial

* Opened draft PR #4900 (branch `Skyline/work/20261022_seed_cpp_releases`). TeamCity's VCS root only builds `master`, `pull/*` and `container/*`, so the seed needs a PR; `.teamcity/` changes trigger nothing (`vcs_trigger_and_paths_config.py`).
* First trial (4230554) failed in seconds: the VCS root enforces a depth-1 clone, so the seed commit was not on the agent. Fixed by `git fetch --depth=1 --no-tags origin %seed.commit%` before the checkout (depth 1 suffices; date and SHA come from HEAD's own commit).
* Second trial 4230560 succeeded in ~20 min on an AWS agent: `pwiz-setup-3.0.26272.10aac2d9-x86_64.msi` (92 MB) + `VERSION`, 308/308 tests (same count as the original 4193616), MSI reachable at `mc-tca-01.s3.../ProteoWizard/bt83/4230560/`. Pinned and tagged `release-2026-09`. No clock change was needed.
* The SHA in the version is 8 hex chars (`git rev-parse --short` in the shallow agent clone), not 7.
* Queued 2026-08..2026-02 as 4230565..4230571, pinned to PR head `b367b702dc`.
* TeamCity REST from scripts: the front proxy returns a bare nginx 403 for XML POST bodies; JSON bodies work. The MCP `trigger_build` cannot pass build parameters, so seed builds were queued with a small REST script using `~/.teamcity-mcp/config.json`.
* Seed results (all SUCCESS, 308/308 tests, pinned + tagged; version day-of-year matches each original month-end build):

  | Month | Build | Version |
  |---|---|---|
  | 2026-09 | 4230560 | 3.0.26272.10aac2d9 |
  | 2026-08 | 4230565 | 3.0.26240.99609d5b |
  | 2026-07 | 4230566 | 3.0.26211.72e04015 |
  | 2026-06 | 4230567 | 3.0.26181.1c640eff |
  | 2026-05 | 4230568 | 3.0.26151.e7e989cc |
  | 2026-04 | 4230569 | 3.0.26120.bb3c999a |
  | 2026-03 | 4230570 | 3.0.26090.f128208e |
  | 2026-02 | 4230760 | 3.0.26058.7b1a2a7b |

* The first 2026-02 run (4230571, not pinned) built and passed everything but failed tcbuild.bat's clean-tree check: the Hardklor submodule stayed at the PR head's commit (its gitlink changed 2026-03-16, #4054). No submodule is in bt83's targets (BiblioSpec's `HardklorReader.cpp` is its own file reader), so Mar-Sep were unaffected. The seed step now runs `git submodule update --init --recursive --force --depth 1` (seed PR head `47e9787c39`).
* Website design (ProteoWizard/web): Monthly reads `releases/bt83-monthly.xml` (same format as `bt83.xml`), Beta reads `releases/bt83.xml`; the selector shows only for the bt83 options, default Monthly. The archive dropdown reads `releases/bt83-archive.json` = `{"releases": [{"month", "version", "buildId", "commit", "artifacts": [file names]}]}`, newest first; the format is documented in `js/main.js`. Tested in Chrome against a scratch copy with sample release files.
* Publish job design (final, user decision 2026-10-22: releases are permanent, never replaced): every release is tagged `release-YYYY-MM-DD` (its build's finish date, server time); seeds keep `release-YYYY-MM`. The scheduled run releases the previous month's last-finishing default-branch build unless it is already a release, the month has a seed, or that day already has a release (warning). "Release the latest build now" (`--latest`) makes a mid-month release; the month still gets its month-end release. The archive JSON field is `release` (YYYY-MM-DD or YYYY-MM), newest first; `bt83-monthly.xml` = newest release. Seeds are recognized by not being on the default branch (guests cannot see build parameters; a guest dry run leaves seed commits empty). The PR-branch dry run runs as a guest with no credentials. TeamCity auth is `pwiz-commit` / `%TeamCityAuthToken%` like the smart trigger; JSON bodies only; artifact content is read via `/guestAuth` because the S3 redirect rejects a forwarded Authorization header.
* `/code-review xhigh` round 1: 15 findings, 14 fixed (empty `--month` arg, lookupLimit, last-finish consistency, typo, guest dry run, personal-build guard, version from installer-version.txt/VERSION, artifact filter, checkout rule `+:scripts/misc`, `%ci` + UTC fallback in the installer scripts, comments); the shared-version-computation refactor dropped. The replacement-related findings were then made moot by the permanent-release redesign.
* Tests: end-to-end against a fake TeamCity (month-end after mid-month, already released, seed month, same-day clash, --latest, dry run, option conflict); real guest dry runs (scheduled: Sep released by its seed; --latest would release 4230758 as release-2026-10-22); pin+tag round-tripped for real on the unarchived failed build 4230571; website tested in Chrome with the new-format archive.
* Uncommitted on the work branch: `scripts/installer/build.ps1` and `build-linux.sh` now take YYDOY from HEAD's committer date (matching `build/PwizVersion.targets`), falling back to today. Verified on `3f290fc` -> `4.0.26281-3f290fc`, the version TeamCity stamped that day.
