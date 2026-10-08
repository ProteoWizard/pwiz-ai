# TODO-20261007_lf_normalization.md -- Normalize stored line endings to LF repo-wide (pwiz #4604)

> **Status: Completed 2026-10-08.** PR [#4789](https://github.com/ProteoWizard/pwiz/pull/4789)
> (merged 2026-10-08 into `Skyline/work/20260612_net8_port` as `9e2b516bcb`). Follow-ups carried in
> `TODO-20261006_net10_cutover.md` step 0.3. History of the work follows.
>
> **Was: IN PROGRESS 2026-10-07.** PR [#4789](https://github.com/ProteoWizard/pwiz/pull/4789)
> (`Skyline/work/20261007_lf_normalization`, commit `f67b961167`) is open against the port
> branch, cut from `6dd40d8c93` right after #4658 retired the C++ tree. 3,161 files, content
> diff is `.gitattributes` only. Post-#4658 measurement: 11,141 tracked, 2,792 stored CRLF,
> 26 mixed (the C++ mixed files went with the tree). Pins added beyond the plan below:
> `**/*.data/** -text` (every `<Name>Test.data` and `osprey-regression.data` directory) and
> `pwiz_tools/BiblioSpec/tests/{inputs,reference}/** -text`, because the Core Linux .NET and
> Docker/Wine configurations read those as bytes from Linux checkouts; vendor reader data was
> already `binary` via nested attribute files. After renormalize: 6,889 i/lf, 532 i/crlf and
> 2 i/mixed all under pinned paths. The PR's TeamCity run is the dry run; pin whatever fails.
> Remaining after merge: follow-up PR (`.git-blame-ignore-revs`, CodeInspectionTest), the
> `-X renormalize` merge on every open port-branch PR (I can push those for the seven moved
> on 2026-10-06; no force-push needed), the ai/ cleanup in Phase T+1.
> **Trap found 2026-10-07 (fixed in `5ee5a8ba7d`):** a `-text` pin stops git from *filtering*
> a path, but `git add --renormalize .` still re-adds every file from the working tree, and on a
> Windows checkout `core.autocrlf` has already written that tree as CRLF. So 438 pinned
> fixtures whose stored form was LF came out stored CRLF: content identical, bytes not. The
> verification "no unpinned i/crlf remain" cannot see this because the files are pinned. The
> right procedure is renormalize, then `git checkout <base> --pathspec-from-file=<pinned
> files the commit touched>` (paths with spaces break a shell loop; use the file form), then
> verify `git diff --name-only <base> HEAD | git check-attr --stdin text` lists no `unset`
> file whose blob differs from the base. Also learned: the BiblioSpec golden-file tests take
> their inputs from `tests/inputs.tar.bz2` via an MSBuild target with an `obj\` stamp, and a
> reused agent that flips between the old and new layouts can lose the extracted files while
> keeping the stamp (bt83 #22029/#22030 on one cloud agent, 69 "Couldn't open" failures).
> **Second trap, same day (fixed in `c73242d100`): do not pin text fixtures `-text` at all.**
> A `-text` file checks out LF on Windows, which is not what any developer or Windows agent
> ever saw for an LF-stored fixture (autocrlf gave CRLF), and it breaks fixtures whose
> companions hash the CRLF bytes: `UpgradeWithFilesTree.sky` + `.skyl` failed
> TestFilesTreeForm on bt209 #22108 with the "audit log does not match" dialog. Rule: the
> normalization must reproduce the old Windows bytes exactly, which plain `text=auto` does;
> only Linux checkouts of formerly CRLF-stored fixtures change, and the Linux/Wine
> configurations on the PR are the test of that. The pins that stay are the pre-existing
> ones (cpp TestData, mzML/mzXML, vendor reader data via nested .gitattributes). Final PR
> shape: `.gitattributes` + 3,182 renormalized files, three commits (normalize, restore the
> wrongly re-added pinned files, drop the pins).
> **State at handoff 2026-10-07 evening:** head `c73242d100`. Green: bt17 Core Linux (424),
> bt83 Core Windows (657), Osprey Linux (655), Core Windows .NET. **Red: bt209, one test,
> `TestFilesTreeForm`** (audit-log hash mismatch on `UpgradeWithFilesTree.sky` + `.skyl` in
> `TestFunctional/FilesTreeFormTest.data`, builds 4205656/4205723). It passed on the first
> head where that file was stored CRLF and fails where it is LF-stored as at the base, yet
> Brendan reproduces it locally in `C:\proj\review` with the file `w/crlf` on disk, so the
> stale-working-copy explanation is insufficient. Skyline Windows .NET and the Docker/Wine
> container were cancelled and never re-run on this head. Use `C:\proj\review` (on the PR
> branch); no `C:\proj\wt` worktrees.
> **RESOLVED 2026-10-07 night (no PR change needed):** the TestFilesTreeForm failure was a stale
> working copy on the agents, not the PR. Head `5ee5a8ba7d` pinned `**/*.data/** -text`, so a Windows
> checkout of it wrote those LF-stored fixtures as LF. `c73242d100` dropped the pin without changing
> any blob, and git does not rewrite an unmodified working file when only its attribute changes, so
> any agent that had checked out `5ee5a8ba7d` kept LF fixtures. All three bt209 failures ran on "MacCoss
> TeamCity Agent 1"; the #4787 failure (Skyline Windows .NET #508, 4205601) ran on cloud agent
> i-0d401c right after bt83 4205588 built `5ee5a8ba7d` in the same `C:\pwiz`. The fixture itself is
> right: base64(SHA1) of the LF blob converted to CRLF equals the `.skyl` hash `zK3t...`. The "local
> repro" was SkylineTester's cumulative failure column: TestFilesTreeForm passed at 18:55 in
> `C:\proj\review\pwiz_tools\Skyline\SkylineTester-20261007-204442.log`; that run's one failure was
> TestDdaSearchDependencyErrors (crux.exe 0xC0000135 inside the Docker worker, environmental).
> **Verified:** bt209 4205764 queued with "Delete all files before the build" on Agent 1 (which also
> clears its stale `obj\`): 1806/1806 at the unchanged head. Wine container 4205659 on the head ran
> 336 passed / 0 failed (same as port head) and was red only through its bt209 snapshot dependency;
> the re-run 4205767 is green. **#4789 at 22:45: all checks green except the two tarball configs (same on #4619).**
> Lesson: an attribute-only change (adding or removing `-text`) never rewrites working files, so
> pinning a path and unpinning it leaves every machine that saw the pinned head with the pinned bytes;
> fix with a clean checkout, not a code change.
> **Merge probe of the open port-branch PRs** (`git merge -X renormalize c73242d100` into each PR head,
> throwaway clone): clean for #4790 #4787 #4780 #4772 #4769 #4755 #4710 #4602; #4782 #4724 #4717 #4339
> #4750 conflict, but every one already conflicts with the port head alone, so the normalization adds
> no new conflicts. A plain merge (GitHub's button) conflicts on #4790 #4787 #4769 #4755 #4602.
> **Next session handoff**: For detailed startup protocol, read
> `ai/.tmp/handoff-20261008_lf_normalization.md` before starting work.
> Execution plan for GitHub issue [ProteoWizard/pwiz#4604](https://github.com/ProteoWizard/pwiz/issues/4604)
> (opened 2026-08-22). Original plan follows.

## Branch Information
- **Module**: `pwiz`
- **Issue**: #4604 "Normalize stored line endings to LF repo-wide"
- **Precedent**: #3651 / `5747ede7c9` (2025-10-20, UTF-8 BOM removal, 3441 files, squash-merged)
- **Target branch**: `Skyline/work/20260612_net8_port`, after #4658 (retire the C++ tree,
  5359 files) merges into it and before it is promoted to master (expected the week of
  2026-10-05 per Brendan). The old master becomes `Skyline/skyline_26_1_1` for .NET 4.7.2
  Skyline-daily releases and is NOT normalized; neither is `Skyline/skyline_26_1`.
  Decided 2026-10-02: normalize only what becomes the .NET 10 master.

## What the issue proposes (summary)

Add `* text=auto` to `.gitattributes`, `git add --renormalize .`, one commit, full TeamCity run,
`.git-blame-ignore-revs` in the same PR. Developer impact none: Windows checkouts still get CRLF
working files. `--renormalize` alone is NOT sufficient under `core.autocrlf=true`; the attribute
is what makes normalization unconditional. Timing: wait until the .NET port stack merges.

## Measured state (2026-10-02, `git ls-files --eol`)

| | master (`C:\proj\pwiz`) | port branch (`C:\proj\integration`) |
|---|---|---|
| tracked | 14,349 | 15,365 |
| stored LF | 6,013 | 7,166 |
| stored CRLF | 3,802 | 3,568 |
| stored mixed | 530 | 530 |
| `-text` / binary | 3,976 | 4,064 |

CRLF-stored by area on master: `pwiz_tools/Skyline` 2,420, `Bumbershoot` 401, `Shared` 303,
`pwiz/data` 164, `pwiz/utility` 98. By type: `.cs` 1,866, `.resx` 728, `.cpp` 192, `.hpp` 145,
`.csproj` 73, `.sln` 40. The 530 mixed files are almost all C++ under `pwiz/` and `libraries/`.

Fresh friction evidence: PR #4744 (port branch master merge, 2026-09-29) spent two commits
restoring CRLF on 220 files that had drifted to LF on the port branch; its diff is
+107,890/-106,681 on 275 files, nearly all of it line endings.

## Lab-verified mechanics (throwaway repo, this machine, 2026-10-02)

Script: scratchpad `eol_lab/lab.sh`. Results:

| case | result |
|---|---|
| `* text=auto` + `git add --renormalize .` | CRLF blob becomes LF; Windows checkout (`autocrlf=true`) still writes CRLF |
| plain `git merge master` into a pre-normalization branch that edited a CRLF file | **CONFLICT** on that file (this is what GitHub's merge button sees) |
| `git merge -X renormalize master` | clean merge, both sides' edits kept, result stored LF |
| `merge.renormalize=true` config, plain merge | same as `-X renormalize` |
| plain `git cherry-pick` of a post-normalization commit onto a CRLF-stored branch | **CONFLICT** |
| `git cherry-pick -X renormalize` | succeeds, but leaves that one file LF-stored on the un-normalized branch |

The auto cherry-pick workflow (`.github/workflows/cherrypick-pr-to-release.yml` ->
`chambm/gh-backport-action`, `main.py`) runs a plain `git cherry-pick`. It will fail on every
file that is CRLF on the release branch unless the release branch is normalized too.

## Design decisions

1. **Final `.gitattributes`** (port-branch form; master's fixture path is
   `pwiz-sharp/pwiz/test/**/TestData/**` until #4658 lands):
   ```
   * text=auto
   *.sh text eol=lf
   *.bat text eol=crlf
   *.mzml binary
   *.mzML binary
   *.mzxml binary
   *.mzXML binary
   pwiz/**/test/TestData/** -text
   ```
   The explicit `.mzML`/`.mzXML` spellings cost nothing. On Windows `core.ignorecase=true`
   makes `*.mzml` match `.mzML` (verified: 169 `.mzML` files show `attr/-text`), but a Linux
   agent has `core.ignorecase=false`, and `* text=auto` would otherwise start normalizing those
   163 text-stored `.mzML` files there.
2. **Do NOT pre-emptively pin more fixture directories with `-text`.** On Windows every text
   file is CRLF in the working tree today regardless of blob, so Windows tests cannot change.
   Only Linux checkouts see a difference, and only for the CRLF-stored fixtures (inventory
   below). Run the Linux configs on the PR and pin exactly what fails; pinning blindly hides
   EOL sensitivity that already exists for the LF-stored majority.
3. **`.editorconfig` stays `end_of_line = crlf`.** It describes the Windows working tree, which
   is unchanged. Add a comment saying storage is LF and git converts.
4. **The .NET 4.7.2 branches are not normalized** (`Skyline/skyline_26_1`, the coming
   `Skyline/skyline_26_1_1`, older release branches). Consequence: a cherry-pick from the new
   master onto any of them must be `git cherry-pick -X renormalize <sha>`; a plain cherry-pick
   conflicts on every CRLF-stored file it touches. The auto cherry-pick workflow
   (`cherrypick-pr-to-release.yml`) runs a plain cherry-pick and will post its "please
   cherry-pick manually" comment instead. Fixes crossing the .NET 10 / 4.7.2 boundary are
   going to need hand work anyway, so this is accepted; revisit if the workflow is kept alive
   for `skyline_26_1_1`.
5. **`.git-blame-ignore-revs` lands in a follow-up PR**, not the normalization PR: the SHA
   that matters is the squash commit, which does not exist until the merge. List `5747ede7c9`
   (the BOM pass) and the new squash SHA. GitHub blame honors the file automatically; local
   git needs `git config blame.ignoreRevsFile .git-blame-ignore-revs`.
6. **In-flight branches update with one command**: `git merge -X renormalize origin/master`.
   Recommend `git config --global merge.renormalize true` so the plain merge works too.

## When

- **On the port branch, after #4658 merges into it, before the branch is promoted to
  master.** The promotion is the one moment every branch owner is already expected to
  re-point and merge, so the normalization rides inside that window instead of creating a
  second one. Doing it after promotion would mean master itself takes a ~3,300-file commit
  while new branches are being cut from it.
- **There will not be a truly quiet moment.** 13 PRs target the port branch on 2026-10-02
  (#4710, #4712, #4715, #4717, #4724, #4744, #4750, #4751, #4753, #4755, #4756, #4757,
  #4758) and Brendan cannot force them all to merge first. So the plan does not wait for
  zero: it merges whatever is ready that morning, then normalizes, and every remaining PR
  owner runs the one-time `git merge -X renormalize origin/Skyline/work/20260612_net8_port`
  (after promotion, `origin/master`). Verified in the lab to merge cleanly with both sides
  kept.
- **Early in a Pacific workday** so TeamCity is back by afternoon and branch owners can
  merge the same day. Not the same day as the promotion itself; one disruptive event per day.
- Old-master PRs (15 open plus 4 stale: #2766, #3271, #3278, #4574) are unaffected by the
  normalization; they are affected by the promotion, which is a separate announcement.

## Execution steps

### Now (dry run, this week): the port branch already has the final layout once #4658 is in
1. Branch `Skyline/work/YYYYMMDD_lf_normalization` off
   `origin/Skyline/work/20260612_net8_port` (after #4658 merges; before that, off #4658's
   branch to see the final tree); apply the `.gitattributes` above; `git add --renormalize .`.
   Verify:
   ```
   git ls-files --eol | grep -c 'i/crlf'     # expect 0 (eol=crlf .bat files store LF)
   git ls-files --eol | grep -c 'i/mixed'    # expect 0 outside -text paths
   git diff --cached --ignore-cr-at-eol --stat   # expect empty: line endings only
   ```
2. Push the branch, open a **draft** PR against the port branch, let every TeamCity
   configuration run, including the Linux ones (`Osprey Linux .NET`, the msconvert
   Docker/Linux builds). This is the real risk reducer. Pin any fixture that fails with
   `-text`, record why in `.gitattributes`.
3. Send the team email (draft saved in Gmail 2026-10-02): the day, the one-time
   `git merge -X renormalize` for every open branch against the port branch, and that the
   next pull rewrites ~3,300 working files (identical bytes, new mtimes: Visual Studio
   reload prompts, one full rebuild per checkout).
4. Add the merge instruction and the `merge.renormalize` / `blame.ignoreRevsFile` settings
   to `ai/docs/version-control-guide.md`, `ai/docs/new-machine-setup.md` and
   `ai/scripts/Verify-Environment.ps1` ahead of time.

### T-0: merge day (after #4658 is in the port branch, before promotion)
1. Merge whatever port-branch PRs are ready that morning first. Then merge the current
   port branch into the draft branch, repeat the renormalize and the three verification
   commands (files merged since the dry run need normalizing too).
2. Title `pwiz: Normalized stored line endings to LF repo-wide (#4604)`, label `pwiz`,
   `Fixes #4604`, body = the issue's "why" plus the verification output. `/code-review` adds
   nothing on an EOL-only diff; say so in the PR instead of running it.
3. Squash-merge into the port branch when TeamCity is green. Record the squash SHA.
   (`Fixes #4604` only auto-closes on a default-branch merge; close the issue by hand or
   let the promotion carry it.)
4. Same day, PR 2 to the port branch: `.git-blame-ignore-revs` (both SHAs),
   `CodeInspectionTest` mixed-endings check (`pwiz_tools/Skyline/Test/CodeInspectionTest.cs:1355`)
   either removed or re-pointed at the `.bat` worktree requirement, `.editorconfig` comment.
5. Post the merge notice with the one-line merge command, and the `-X renormalize` note
   for anyone cherry-picking to a .NET 4.7.2 branch.
6. The promotion to master happens on a later day, with its own announcement. Once the
   port branch is master, the merge command in the email becomes
   `git merge -X renormalize origin/master`.

### T+1: ai/ cleanup (pwiz-ai master, direct commits)
- `ai/CRITICAL-RULES.md` "Line endings in pwiz": replace with "git stores LF and normalizes on
  commit; write either ending; `.bat` must stay CRLF in the working tree (`eol=crlf`)".
- Remove the fix-line-endings steps: `ai/scripts/Skyline/Build-Skyline.ps1:165`,
  `ai/scripts/Osprey/Build-Osprey.ps1:258`, `ai/scripts/CarafeSharp/Build-CarafeSharp.ps1:99`,
  `ai/scripts/Osprey/Update-OspreyResxDesigners.ps1:73`. Retire `ai/scripts/fix-crlf.ps1`
  (keep until the release branch is also normalized; it is still correct for other checkouts).
- `ai/scripts/Verify-Environment.ps1`: keep the `core.autocrlf=true` recommendation (it is
  what gives CRLF working files for Visual Studio), add `merge.renormalize` and
  `blame.ignoreRevsFile` checks.
- `ai/docs/osprey-development-guide.md:1696`: the `maccoss/osprey` `autocrlf=input` note is
  about a different repo and stays.
- Personal memory: nothing to keep; the rule lives in CRITICAL-RULES.

## Risk register

| risk | who sees it | mitigation |
|---|---|---|
| CRLF-stored fixtures compared byte-exact on Linux CI | Linux agents only | T-7 dry run; `-text` pin only on failure. Candidates: `pwiz_tools/BiblioSpec/tests/reference/*.check,*.report,*.skip-lines` (compared by `CompareTextFiles.cpp`, CR handling not verified), `pwiz_tools/Skyline/TestTutorial/TutorialAuditLogs/**/*.log` (36), MSstats `.csv` under `Skyline/Test/MSstats` (20), `.sky`/`.skyr` under `Skyline/Test*` (35) |
| GitHub merge button shows conflicts on every open PR that touched a CRLF file | PR owners | one-time `git merge -X renormalize origin/master`; announced T-7 |
| cherry-picks from the .NET 10 master to `skyline_26_1` / `skyline_26_1_1` conflict; the auto cherry-pick workflow posts "cherry-pick manually" | whoever back-ports a fix | `git cherry-pick -X renormalize <sha>` by hand; documented in version-control-guide; accepted because cross-runtime back-ports need hand work regardless |
| `git blame` attributes ~3,300 files to the normalization commit | everyone | `.git-blame-ignore-revs` (PR 2); GitHub honors it automatically, local git via config; Rider/VS blame views do not read it |
| every checkout rewrites ~3,300 files on next pull | everyone, each checkout/worktree | identical bytes; expect VS reload prompts and one full rebuild; `C:\proj` alone holds 7 pwiz checkouts |
| developer with `core.autocrlf=input` or `false` on Windows | that developer | `text=auto` + `false` gives CRLF via `core.eol=native`; `input` gives an LF working tree by their own choice; neither churns the repo any more |
| stale PRs (#2766, #3271, #3278, #4574) become more conflicted | nobody active | already conflicted; no action |
| the port branch generates new CRLF drift between dry run and T-0 | normalization PR | T-0 step 1 re-runs renormalize on current master |

## Open-PR exposure scan (2026-10-02)

Which open PRs touch files that the normalization commit will rewrite. Method: each PR's
changed files (GitHub API, `status != added`) intersected with the `i/crlf` and `i/mixed`
inventory of its base branch (port branch for port PRs, master for master PRs). A PR whose
touched files are all LF-stored shares no hunks with the normalization and merges without
`-X renormalize`. Skipped: #4619 (is the port branch), #4658 (merges before this). None of
the scanned PRs adds new CRLF files (first 40 added source files per PR checked).

PRs against the port branch (affected by the normalization itself):

| PR | author | files | CRLF/mixed touched | exposure |
|---|---|---|---|---|
| #4750 owned-form close cascade | chambm | 237 | 132 | high |
| #4755 INNO update check | nickshulman | 58 | 14 | needs `-X renormalize` |
| #4763 DNS failure reporting | brendanx67 | 19 | 12 | needs `-X renormalize` |
| #4339 CV update | chambm | 35 | 6 | needs `-X renormalize` |
| #4753 waters_connect port | bspratt | 26 | 3 | needs `-X renormalize` |
| #4757, #4724, #4717, #4715, #4710 | maccoss | 5-188 | 0 | none (Osprey/CarafeSharp trees are LF-stored) |

PRs against the old master (unaffected until they re-target the promoted master; then the
same one-time merge):

| PR | author | files | CRLF/mixed touched |
|---|---|---|---|
| #4301 observed IM/CCS | bspratt | 66 | 42 |
| #4170 peak scoring | nickshulman | 97 | 36 |
| #4602 DPI awareness | rita-gwen | 56 | 35 |
| #4426 open from .sky.zip | nickshulman | 59 | 31 |
| #3861 screenshot comparison | chambm | 2249 | 23 |
| #4498 Waters lockmass | bspratt | 33 | 20 |
| #4574 external | kpnovoselov | 39 | 14 |
| #4130 relative standard error | apsoras | 15 | 13 |
| #4391 mod site localization | rita-gwen | 17 | 12 |
| #4422 mzML CV filtering | bspratt | 45 | 11 |
| #4683 waters_connect CE | rita-gwen | 14 | 8 |
| #4546 cancel export report | nickshulman | 36 | 8 |
| #2766, #3271 | external | 9, 14 | 7, 11 |
| #4303 Sage DDA | chambm | 12 | 3 |
| #4745 formatting dialog | rita-gwen | 3 | 2 |
| #3278 | poshul | 2 | 1 |
| #4495, #4154 | rita-gwen, bspratt | 4, 4 | 0 |

Script: scratchpad `pr_crlf_scan.sh` (gh + the two `git ls-files --eol` dumps). Re-run on
T-0 morning; the list changes daily.

## Verification of success

- `git ls-files --eol | grep -c 'i/crlf'` on master is 0 and stays 0 (a nightly or
  CodeInspection-style check could assert this; `text=auto` makes it mechanical, so a check is
  optional).
- A `sed -i` or LLM rewrite of any file produces a diff of only the edited lines.
- `ai/scripts/fix-crlf.ps1` reports nothing to do on every subsequent branch, then is deleted.

## Open questions for Brendan

1. Which day does #4658 merge into the port branch, and which day is the promotion? The
   normalization goes between them, on its own day.
2. Keep the `CodeInspectionTest` mixed-endings check as a `.bat`-only guard, or delete it?
3. Does the auto cherry-pick workflow stay pointed at `skyline_26_1`, move to
   `skyline_26_1_1`, or get retired now that cross-runtime back-ports need hand work?

## Progress Log

### 2026-10-08 - Merged

PR #4789 squash-merged into `Skyline/work/20260612_net8_port` as `9e2b516bcb`, tree identical to the
tested head `c73242d100`: `.gitattributes` plus 2,742 renormalized files against the port head
`e35b05852f`. Final CI on that head: bt209 1806/1806 (clean checkout on Agent 1), Wine container
336/0, bt83, bt17, Osprey Windows/Linux, native shims and code inspection green; only the two subset
source tarball configs red, as on the port branch itself (they call the deleted `tcbuild.sh`). No
fixture needed a `-text` pin. `Fixes #4604` is in the squash message, so the issue closes when the
promotion fast-forwards master. Deferred, tracked in `TODO-20261006_net10_cutover.md` 0.3: the
follow-up PR (`.git-blame-ignore-revs` with `5747ede7c9` and `9e2b516bcb`, `.editorconfig` comment,
CodeInspectionTest decision), the `-X renormalize` merges on the open port-branch PRs, and the T+1
ai/ cleanup. Open questions 2 and 3 above are still Brendan's.
