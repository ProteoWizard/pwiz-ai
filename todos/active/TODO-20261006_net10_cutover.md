# TODO-20261006_net10_cutover.md -- Cut-over: promote the .NET 10 port branch to master

> **Status: PLAN.** Written 2026-10-06 from a verified snapshot of the repository, TeamCity
> checks and branch protection. Nothing below has been executed. Brendan owns the sequence;
> Matt owns the TeamCity side.

## Branch Information
- **Port branch**: `Skyline/work/20260612_net8_port`, head `490a4d3825` (PR #4619, 91 curated
  commits, force-pushed after the history rewrite; full history archived at
  `archive/net10-port-full-history`)
- **Old master**: `0c7a9167a6`. **It is an ancestor of the port head** (0 commits on master
  that the port lacks). The promotion is a fast-forward.
- **New .NET 4.7.2 daily branch**: `Skyline/skyline_26_1_1` (to be created from the last
  4.7.2 Skyline-daily tag)
- **Module**: `pwiz`
- **Related**: `TODO-20260612_net8_port.md` (the port), `TODO-20261007_lf_normalization.md` (LF
  storage; slots in between #4658 and the promotion)

## Verified state (2026-10-06)

| item | state |
|---|---|
| #4619 mergeability | `MERGEABLE` but `BLOCKED`: master's required status checks are the six **old cpp contexts** (Core Windows/Linux x86_64, Bumbershoot x2, Docker container (Wine x86_64), Skyline master and PRs (Windows x86_64)); the port head posts the .NET ones instead |
| .NET checks on the port head | all green: Core Linux .NET (421 tests), Core Windows .NET (650), Osprey Linux .NET (655), Osprey Windows .NET (655), Skyline Windows .NET (1806), Docker container .NET (Wine x86_64), Skyline code inspection. CodeQL check failed in 5 s (not required; look at it separately) |
| Branch protection | `strict: true` (branch must be up to date), 0 required reviews, `enforce_admins: false` (an admin push bypasses the checks), force-push disabled |
| #4658 retire the C++ tree | still OPEN against the port branch |
| PRs open against the port branch | 11: #4782, #4780, #4772, #4769, #4755, #4750, #4724, #4717, #4710, #4658, #4339. **Every one now shows 2,100-2,500 changed files**: their branches are based on the pre-rewrite history, so GitHub diffs them against old master |
| Active PRs against old master | 14 besides #4619 (#4773, #4771, #4683, #4602, #4574, #4546, #4426, #4422, #4391, #4303, #4301, #4170, #4154, #4130) |
| Version numbers | **both lines produce `26.1.1.DDD`**: master via `Jamfile.jam` (`SKYLINE_YEAR 26 / ORDINAL 1 / BRANCH 1`), the port via `pwiz_tools/Skyline/SkylineVersion.targets` (same three values) |
| Nightly branch selection | not in SkylineNightly code: TeamCity VCS roots `pwiz Github Skyline_Integration_Only` / `Skyline_Release_Only` decide what "integration" and "release" build. SkylineNightly maps master -> `bt209`, integration -> `ProteoWizard_SkylineIntegrationBranchX8664`, release -> `ProteoWizard_WindowsX8664SkylineReleaseBranchMsvcProfessional` |
| SkylineNightlyShim | installed on every nightly machine, never auto-updated, hard-codes **`bt209`** as the source of `SkylineNightly.zip` (`SkylineNightlyShim/Program.cs:40`) |
| CI trigger config on the port (`scripts/misc/vcs_trigger_and_paths_config.py`) | `master` targets already the .NET configs (`bt209` commented out); `release` targets still the cpp/MSVC configs. `smartBuildTrigger.py` maps any `skyline_*` base branch to `release`, so `skyline_26_1_1` is covered |
| Nightly trigger config | master -> `ProteoWizard_SkylineWindowsNetPerfTutorialTests`; release -> the cpp perf/tutorial config |
| Nightly results (screenshot 2026-10-06) | Integration: 8 machines, 1 failure (TestRInstaller, UW5), 1 hang (TestFilesTreeForm, UW6); Leak: 1 leak (AgilentMseChromatogramTest, UW8); Perf: clean. Comparable to a normal master day |

## State checked 2026-10-07 night

- **0.5 is in place**: Matt moved the .NET steps into the parent configs. bt209 on the port head
  (4205492) ran 1806 tests and its versioned settings publish `SkylineNightly.zip` and
  `SkylineTester.zip`; bt83, bt17 and the Wine container now post .NET results under the old names.
- **0.6 is already done**: master's required contexts are now `teamcity - Core Windows x86_64`,
  `teamcity - Skyline master and PRs (Windows x86_64)`, `Skyline code inspection`, `teamcity - Core
  Linux x86_64` (strict). The port head posts all four green, and `origin/master` is still an
  ancestor of the port head (fast-forward OK).
- **Three reds on #4619 that are not required but will show on every master commit after the
  fast-forward:**
  - `Core subset source tarball` (bt81) and `BiblioSpec subset source tarball`: both have a
    `buildDependencyTrigger` on bt17 with `branchFilter +:*` and run `scripts/misc/tcbuild.sh`,
    which #4658 deleted ("Cannot run program scripts/misc/tcbuild.sh"). bt17 now builds .NET, so they
    can only fail. Their dependents `ProteoWizard_WindowsX86subsetNoVendorDll` and
    `ProteoWizard_BiblioSpecLinuxX8664subset` go with them. **Matt**: pause them, or re-point the
    trigger at a cpp release-branch config if 4.7.2 source tarballs are still published.
  - CodeQL `Analyze (java-kotlin)`: the repo's CodeQL default setup lists `java-kotlin`. Master passes
    because it still has the 9 `pwiz/utility/bindings/java` RAMPAdapter files; the port deleted them,
    leaving only the `.teamcity` Kotlin DSL, which autobuild cannot compile ("CodeQL could not process
    any code written in Java/Kotlin"). **At promotion** (admin, same moment as the fast-forward):
    ```
    gh api -X PATCH repos/ProteoWizard/pwiz/code-scanning/default-setup --input - <<'EOF'
    {"state":"configured","languages":["actions","c-cpp","csharp","javascript-typescript","python"]}
    EOF
    ```
- "MacCoss TeamCity Agent 1" got a full clean checkout 2026-10-07 21:31 (bt209 4205764), which
  clears the stale `obj\` noted in 2.4; its `zSmartTrigger` clone is a separate directory and is
  untouched.

## The sequence

### Phase 0: this week, before any branch moves

0.1 **Rebase the 11 open port-branch PRs onto the rewritten branch.** DONE 2026-10-06 for
    7 of 9 (all three authors gave the go-ahead by email): #4772, #4769, #4724, #4339 rebased
    commit by commit; #4755, #4717 replayed as one commit (their own commits were intertwined
    with the old port history); #4710 replayed as one commit with 8 files hand-resolved
    against the localization pass and the SpectraCache lanes work, plus resx entries so the
    four Osprey CodeInspection tests pass (676/676). Every branch built locally before the
    `--force-with-lease` push; a comment on each PR gives the owner the `reset --hard`
    recipe. #4782 and #4780 were already on the new history. **Left for Matt: #4750 (11
    conflicting files) and #4658** (its net diff conflicts only on `Pwiz.sln`, but a
    commit-by-commit rebase conflicts in 34 files at its first commit). Fork points, patches
    and logs are in the session scratchpad (`patches/`, `builds/`). Lesson: `git diff` here
    runs the `astextplain` textconv on `.pdf`/`.dot`, so build replay patches with
    `--no-textconv`; and a worktree needs `-VendorLicenses` on `Build-Skyline.ps1` or the
    Mascot parser archive never extracts and BiblioSpec fails before any PR code compiles.
0.2 **Land #4658** (retire the C++ tree) on the port branch. DONE 2026-10-07 by Matt
    (`6dd40d8c93`).
0.3 **LF normalization** on the port branch, per `TODO-20261007_lf_normalization.md`. **MERGED
    2026-10-08 as `9e2b516bcb` (#4789).** Still to do: follow-up PR (`.git-blame-ignore-revs` with
    `5747ede7c9` + `9e2b516bcb`, `.editorconfig` comment, CodeInspectionTest decision); the
    `-X renormalize` merge on each open port-branch PR (probe 2026-10-07: clean for #4790 #4787
    #4780 #4772 #4769 #4755 #4710 #4602); the T+1 ai/ cleanup in the LF TODO. Earlier: IN PROGRESS
    2026-10-07: PR #4789 open against the port branch, cut from `6dd40d8c93`; CI is the dry
    run. After it merges: follow-up PR (blame-ignore-revs, CodeInspectionTest), then the
    `-X renormalize` merge on every open port-branch PR before the promotion re-targets them.
0.4 **Decide the version numbers** (see Decisions, D1). DECIDED; implemented as PR #4786,
    **squash-merged into the port branch 2026-10-07 as `ad837d5724`** (the Jamfile comment
    hunk was dropped first so it cannot conflict with #4658); work branch deleted:
    `SkylineVersionBranch` 2, the two format-guard tests skip only on 9, comments. Verified
    locally: build stamps 26.1.2.279 and both tests run and pass. `skyline_26_1_1` needs
    nothing. Merge before the promotion so the first .NET 10 daily is 26.1.2.
0.5 **TeamCity (Matt)**: make `bt209` build the .NET 10 tree. The shim on every nightly machine
    downloads `SkylineNightly.zip` from `bt209` and cannot be changed remotely, and SkylineNightly
    downloads master's `SkylineTester.zip` from `bt209` too. The config id must survive; its
    build steps become the ones in `ProteoWizard_SkylineWindowsNet`, with the same artifact
    names. Verify by downloading both zips from `bt209?branch=master` after the promotion.
0.6 **Branch protection**: replace the six required contexts with the .NET ones the port head
    posts (`teamcity - Core Linux .NET`, `Core Windows .NET`, `Osprey Linux .NET`, `Osprey
    Windows .NET`, `Skyline Windows .NET`, `ProteoWizard and Skyline Docker container .NET (Wine
    x86_64)`, `Skyline code inspection`). `gh api -X PATCH
    repos/ProteoWizard/pwiz/branches/master/protection/required_status_checks` or the settings
    page. Do this the morning of the promotion, not earlier: until master is the .NET tree,
    old-master PRs cannot satisfy the new contexts.
0.7 **Announce the plan** (email draft; see Communication).

### Phase 1: last 4.7.2 Skyline-daily and the new 4.7.2 branch (Brendan's steps 1-2)

1.1 Build and publish the last 4.7.2 Skyline-daily from master as usual; tag
    `Skyline-daily-26.1.1.DDD`. DONE 2026-10-06: `Skyline-daily-26.1.1.279` at `796129c9ee`
    (the version-bump commit, pushed to master).
1.2 `git branch Skyline/skyline_26_1_1 <that tag>` and push. DONE 2026-10-06: branch at
    `796129c9ee`, pushed; `C:\proj\daily` switched to it. Nothing else on master after this
    point except the fast-forward.
1.3 On `skyline_26_1_1`: apply the version decision (D1) if it changes this branch; update
    `.github/workflows/cherrypick-pr-to-release.yml` `pr_branch` if D3 says the label targets
    this branch. Commit to the branch (not master: master is about to become the port).
1.4 Local folder: `C:\proj\daily` is already a master checkout used for daily releases;
    `git checkout Skyline/skyline_26_1_1` there. `C:\proj\pwiz` stays on master.
1.5 Team notice, in the release-branch template's words: "treat `skyline_26_1_1` as if we
    just made a major release from it: 4.7.2 fixes go there by cherry-pick or direct PR;
    everything else goes to the new master."

### Phase 2: the promotion (Brendan's step 3)

2.1 Pre-flight, same morning: port head green on all .NET configs; #4658 (and 0.3 if done)
    merged; every port-branch PR rebased (0.1); `bt209` rebuilt from the port branch at least
    once (0.5); branch protection updated (0.6).
2.2 **Fast-forward, do not use the merge button.** From any checkout:
    ```
    git fetch origin
    git merge-base --is-ancestor origin/master origin/Skyline/work/20260612_net8_port && echo ff-ok
    git push origin origin/Skyline/work/20260612_net8_port:master
    ```
    Why: "Create a merge commit" adds a merge whose second parent is already an ancestor,
    for nothing; "Rebase and merge" rewrites all 91 commits and flattens the six recreated
    master merges Matt and Brendan just curated. A fast-forward keeps the SHAs that the
    archive, the TODO and the nightly Git-hash column already cite. GitHub marks #4619 merged
    when its head becomes reachable from master; confirm, and close it by hand if not.
2.3 Re-target the remaining port-branch PRs: `gh pr edit <N> --base master` for each.
    Only then delete the port branch (GitHub closes PRs whose base disappears).
2.4 Watch the first master builds: `zSmart build trigger` on master, the .NET configs, the
    GitHub Actions (`build_and_test.yml`, CodeQL). `bt209?branch=master` must publish
    `SkylineTester.zip` and `SkylineNightly.zip`. **Known trap (found 2026-10-06 on #4786):**
    `scripts/misc/smartBuildTrigger.py:99` prepares the base branch with
    `git checkout <base> && git pull origin <base>`; on the persistent agent ("MacCoss
    TeamCity Agent 1") the long-lived `C:\teamcity\zSmartTrigger` clone still holds the
    pre-rewrite port branch, so the pull fails and the trigger exits 1 with no checks posted.
    Cloud agents have fresh clones and are fine. Re-queue the trigger to dodge it; the
    durable fix is `git fetch origin <base> && git checkout -B <base> FETCH_HEAD`, or Matt
    clears that agent's clone. Fades after promotion since master only fast-forwards.
2.5 Old-master PR authors: each of the 14 decides, per PR, between re-targeting to
    `skyline_26_1_1` (4.7.2-only work) and `git merge origin/master` (brings the whole port
    into the branch; expect csproj/resx conflicts since the port rewrote every csproj to SDK
    style and renamed zh-CHS resx to zh-Hans). #4773/#4771 (Inno handoff) are the ones whose
    answer is probably "both".

### Phase 3: nightly machines back to master (Brendan's step 4)

3.1 Each nightly machine: change the scheduled task's run spec from `integration/...` to
    `master/standard`, `master/leak` or `master/perf` (SkylineNightly form, Run1/Run2). The
    form already offers every branch x type combination; no SkylineNightly code change is
    needed for the machine side.
3.2 SkylineNightly code: the `TEAM_CITY_BUILD_TYPE_64_MASTER = "bt209"` constant stays valid
    only because 0.5 keeps the id. If Matt instead creates a new config, the constant changes
    in both `Nightly.cs:53` and `SkylineNightlyShim/Program.cs:40`, and every machine needs a
    shim reinstall; avoid. Verified 2026-10-06 on the port head: the form and parser already
    accept master x {standard, leak, perf}; `ResolveBranchUrl` handles a .NET-built
    SkylineTester (stamp in `SkylineTester.dll`) as well as a C++ one (`Version.cpp`);
    `ProteoWizard_SkylineWindowsNet` publishes both `SkylineNightly.zip` and
    `SkylineTester.zip`. `SkylineNightly.zip` is framework-dependent (no runtime closure);
    every nightly machine already has the .NET 10 Desktop Runtime via Visual Studio 2026 and
    has run Integration tests, so no runtime install is needed. The only open item is 0.5.
3.3 Results land in `Nightly x64`, `Performance Tests` and the leak container as before. The
    Integration containers go quiet; leave them, the history is useful.
3.4 The daily report: `ai/docs/daily-report-guide.md` nightly-folder table (line ~762) loses
    the Integration row; `Invoke-DailyReport.ps1`'s guarded fast-forward of `C:\proj\pwiz`
    takes the promotion on its next run (it is a fast-forward).

### Phase 4: TeamCity "Release" (Brendan's step 5)

4.1 Point `pwiz Github Skyline_Release_Only` at `Skyline/skyline_26_1_1`. The release
    configs are still the cpp/MSVC ones, which is what a 4.7.2 branch needs, and the trigger
    config already maps `skyline_*` to `release`.
4.2 Consequence: `Skyline/skyline_26_1` (26.1 patches) loses its TeamCity coverage unless a
    second root is added. Decide (D2).
4.3 Nightly machines on `release/...` runs follow the root automatically.

### Phase 5: ai/ and local checkouts (after 2.2)

- `ai/docs/release-cycle-guide.md` Current State: add `skyline_26_1_1` and what it is for;
  Release Folder table.
- `ai/docs/daily-report-guide.md` nightly-folder table; `ai/claude/commands/pw-daily-research.md`
  checkout mapping; `ai/mcp/LabKeyMcp/tools/computers.py` container list if runs move.
- `ai/docs/github-repo-guide.md` and `get_project_status` guidance: `C:\proj\pwiz` = .NET 10
  master, `C:\proj\daily` = `skyline_26_1_1`, `C:\proj\integration` retired (or re-pointed).
- `ai/docs/osprey-development-guide.md:1758-1770`: delete the "while #4619 is open" subsection
  as it says to.
- `ai/CRITICAL-RULES.md`, `skyline-development` skill, `ai/scripts/Skyline/*.ps1`: anything
  that assumes net472 paths (`bin\x64\Release`) now describes `skyline_26_1_1` only.
- `TODO-20260612_net8_port.md` -> completed once 2.2 is done.

## Decisions needed

- **D1. Version numbers. DECIDED 2026-10-06 (Brendan):** the 4.7.2 line on
  `skyline_26_1_1` keeps `26.1.1.DDD`; the .NET 10 master becomes **`26.1.2.DDD`**. Same
  shape as a normal release, where `skyline_26_1` kept 26.1.0 and master moved to 26.1.1:
  the line that moves forward takes the next digit, a 4.7.2 patch `26.1.1.350` can ship
  while .NET 10 users are on `26.1.2.299`, and 26.1.2 is newer than 26.1.1 whatever the day
  number. Before the next release the digit goes to 9 as usual (`26.1.9` for a 26.2 release
  in Nov/Dec 2026, `27.0.9` for 27.1 in Jan 2027). No document-format or schema change.
  **Code that interprets the digit** (checked on the port head): `Install.Type` treats any
  nonzero digit as `daily`, so 2 is a daily build everywhere (update URL, title, upgrade
  path); `SkylineVersion.CURRENT` and `ToolService` only carry it. **Two tests must
  change**: `Test/DocumentSerializerTest.cs:44` and `Test/SrmDocumentTest.cs:1577` skip the
  format/schema guard when `Install.Build > 1`, written when only 0/1/9 existed; with a 2
  they would silently stop running on master. Change both to skip only for 9. **Where to
  set it**: `pwiz_tools/Skyline/SkylineVersion.targets` `SkylineVersionBranch` 1 -> 2 on the
  port branch before promotion (the Jamfile on `skyline_26_1_1` stays at 1). Update the
  digit tables in `ai/docs/release-guide.md` (Version Numbering) and
  `ai/docs/release-cycle-guide.md` (Quick Reference), and the comments in
  `SkylineVersion.targets` and `Jamfile.jam`.
- **D2. Which release branch keeps TeamCity.** `skyline_26_1_1` (daily 4.7.2) vs
  `skyline_26_1` (26.1 patches), or both roots.
- **D3. What the "Cherry pick to release" label targets** after the cut-over:
  `skyline_26_1_1` (most 4.7.2 back-ports), `skyline_26_1` (true release patches), or retire
  the label while the lines are different runtimes. Plain cherry-picks across the LF
  normalization conflict either way (`-X renormalize` by hand).
- **D4. Whether the LF normalization goes before the promotion** (0.3) or straight after.
- **D5. Port branch deletion timing** after the re-targeting in 2.3.

## Communication

- Email 1 (now): the plan and dates; the version decision; "rebase your port-branch PR";
  "old-master PRs: choose a destination".
- Email 2 (after 1.2): `skyline_26_1_1` exists, treat it as a release branch.
- Email 3 (after 2.2): master is .NET 10; the one-time merge for open branches; nightly
  machines switch tomorrow.
