# Monthly pinned releases of Core Windows x86_64 (bt83) and a release archive on the website

## Branch Information
- **Branch**: `Skyline/work/20261022_monthly_releases`
- **Base**: `master`
- **Created**: 2026-10-22
- **Status**: In Progress
- **GitHub Issue**: [#4899](https://github.com/ProteoWizard/pwiz/issues/4899)
- **Module**: `pwiz`
- **PR**: (pending)

## Objective

Publish a monthly ProteoWizard release from Core Windows x86_64 (bt83). When a new month starts, the last successful default-branch bt83 build of the previous month is pinned and tagged `release-YYYY-MM` in TeamCity. The pwiz website (ProteoWizard/web) gets an archive page for browsing and downloading past monthly releases. To seed the archive, the last build of each of Feb-Sep 2026 is rebuilt and pinned.

Out of scope: Linux (bt17) and Bumbershoot artifacts, and manual mid-month pins. The seed builds only need to produce the Windows installer.

The issue body holds the full technical detail: how the website resolves downloads, the two installer generations, retention, the seed commit table and the seeding design.

## Tasks

- [ ] Seed PR (never merged): `bt83.xml` from `2deb47a782` + `seed.commit` parameter + first step `git checkout --detach %seed.commit%` + artifacts limited to `build-nt-x86/*.msi` and `build-nt-x86/VERSION`
- [ ] Trial seed build for 2026-09 (`10aac2d`): agents still build the C++ tree, and `VERSION` = `3.0.<commit YYDOY>.10aac2d`
- [ ] Remaining 7 seed builds; pin + tag each `release-YYYY-MM` with the seed commit in the pin comment
- [ ] Monthly pin job (1st of the month): pin + tag the last successful default-branch bt83 build of the previous month
- [ ] Archive metadata file uploaded to `htdocs/releases/` (builds tagged `release-*` on any branch)
- [ ] Website archive page in ProteoWizard/web (`.msi` for the C++ months, three `.exe` variants from 2026-10)
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
