# TODO-20260627_osprey_rename.md -- Rename OspreySharp -> Osprey (retire the "OspreySharp" name)

> Mike MacCoss has agreed the C# project becomes the official **Osprey**.
> "OspreySharp" was a hedge: Claude + Brendan coined it (April 2026) as a
> C# counterpart to the Rust `maccoss/osprey` POC, unsure a C# port could
> match it. It could -- and did. Mike agreed at the 2026-05-29 lab meeting;
> on 2026-06-03 he made `maccoss/osprey` LGPL (no forking) and announced it
> unsupported. Osprey going forward is the C# implementation in pwiz.
>
> **Goal: rename OspreySharp -> Osprey and remove the term "OspreySharp"
> from the ProteoWizard/pwiz and pwiz-ai (ai/) repos -- ideally one pwiz PR
> plus coordinated ai-master commits.** Large but mechanical; low-risk
> because no committed output embeds the name (see Invariant below).
>
> **This sprint is also a deliberate delegation trial** -- run it as a dev
> lead using Sonnet/Haiku "junior devs" and report how it went. See "Headline
> goal: run this as a dev lead with junior devs" below; that retro is a
> co-equal deliverable with the rename itself.

## Branch Information

- **Branch**: `Skyline/work/20260627_osprey_rename`
- **Base**: `master`
- **Created**: 2026-06-27
- **Status**: Completed
- **GitHub Issue**: (none)
- **PR**: [#4335](https://github.com/ProteoWizard/pwiz/pull/4335) (merged 2026-06-27 as 1ca152c5)

## Scope survey (measured 2026-06-27 via `git grep`)

- **pwiz**: 726 occurrences across 207 files. All but 9 files are inside
  `pwiz_tools/OspreySharp/`. The 9 cross-references:
  `.github/workflows/build_and_test.yml` (path filters
  `pwiz_tools/OspreySharp/**`), `.gitignore`, `pwiz_tools/Jamfile.jam`
  (`build-project-if-exists OspreySharp`), `scripts/misc/{nightly,vcs}_trigger_and_paths_config.py`,
  and `pwiz_tools/Shared/PortableUtil/*` (comment-only mentions in
  `ArgUsage.cs`, `ArgumentBase.cs`, `CommandStatusWriter.cs`,
  `PortableUtil.csproj` -- PortableUtil is shared, so rebuild AutoQC /
  SkylineBatch after touching it even though these are comments).
- **ai/**: 1,776 occurrences across 142 files -- but the bulk is in
  `todos/completed/` historical records (see Decision 1). Forward-facing:
  `scripts/OspreySharp/*`, `docs/osprey-development-guide.md` +
  `osprey-crossimpl-validation-guide.md`, `claude/skills/osprey-development/SKILL.md`,
  `claude/hooks/Inject-PathBasedSkill.ps1` (matches the pwiz path),
  `MEMORY.md` + memory files, active todos.

## Target name map

| From | To |
|------|-----|
| dir `pwiz_tools/OspreySharp/` | `pwiz_tools/Osprey/` |
| `OspreySharp.sln` | `Osprey.sln` |
| projects `OspreySharp[.Core/.IO/.Chromatography/.Scoring/.FDR/.ML/.Tasks/.Diagnostics/.Test]` | drop "Sharp" -> `Osprey[.Core/...]` |
| namespace root `pwiz.OspreySharp[.X]` | `pwiz.Osprey[.X]` (~172 decls + every `using` / qualified ref) |
| `AssemblyName` `OspreySharp` (exe) | `Osprey` (binary `Osprey.exe` / `Osprey`; `dotnet Osprey.dll`) |
| ai `scripts/OspreySharp/` + `Build-OspreySharp.ps1` etc. | `scripts/Osprey/` + `Build-Osprey.ps1` etc. |

**Do NOT change** (already "osprey"/"Osprey", and the rebrand keeps them):
class names (`OspreyTask`, `OspreyCommandArgs`, ...), env vars (`OSPREY_*`),
the `.osprey.task` sidecar suffix, `OSPREY_VERSION_OVERRIDE`,
`osprey-regression.data`, file suffixes (`.scores.parquet`, etc.), the Rust
checkout `C:\proj\osprey`.

## Hard invariant: byte-identical output

The committed regression golden (`osprey-regression.data/`) has **zero**
"OspreySharp" occurrences (verified) -- the producing assembly name does
not leak into the blib / metadata / dumps. So the rename must not change
any pipeline output. Gate the PR on the existing correctness gate (renamed
`Osprey/regression.ps1`) staying green at 1e-9, plus build + inspection +
all tests, plus a final `git grep OspreySharp` returning **zero** in the
chosen scope.

## Suggested method (mechanical-first, model-supervised)

1. **Opus does the structural / risky moves itself** (cross-file
   consistency is where this must not slip):
   - `git mv` the dir, the 10 project folders, the `.sln`, and rename each
     `.csproj`; update every `ProjectReference` path, `InternalsVisibleTo`,
     `AssemblyName`, and the `.sln` project entries. Watch `ProjectGuid`
     pinning (see `reference_sdk_project_pinned_guid` -- SDK csprojs need
     explicit GUIDs; keep the GUIDs, only change names/paths).
   - Fix the 9 pwiz cross-references (workflow path filters, Jamfile,
     `.gitignore`, `scripts/misc/*.py`, PortableUtil comments).
   - Update `GenerateUsageHtml()` / workflow-HTML / README prose, then
     regenerate `Documentation/Help/en/CommandLine.html` (the self-healing
     test rewrites it; just re-run and commit).
2. **Bulk token substitution** for namespaces / usings / qualified refs is
   best done with a deterministic scripted sweep (PowerShell `-replace` /
   `git mv` + sed), not by hand or by burning model tokens -- exact and
   reviewable in the diff. Opus authors + runs it.
3. **Verify**: full pwiz gate (`Build-Osprey.ps1 -RunTests -RunInspection`,
   `Osprey/regression.ps1 -Dataset All`) + `git grep OspreySharp` == 0.
4. **ai/ repo** (separate, direct to master): rename `scripts/Osprey/` +
   scripts, fix internal pwiz-path refs, the path-based-skill hook + skill,
   the guides, `MEMORY.md`/memory files, active todos. **Ordering caveat:**
   the build wrappers live in ai/ but invoke the pwiz path -- update the
   wrapper to point at `pwiz_tools/Osprey` early so this session can still
   build during the rename.

## Headline goal: run this as a dev lead with junior devs

This sprint is **as much an experiment in delegation as it is a rename.**
The framing:

- **Brendan = dev manager** -- sets the goal, not the method.
- **You, the Opus 4.8 `/pw-continue` session, = dev lead.**
- **Sonnet / Haiku sub-agent sessions = junior devs / interns.**

The rename is the vehicle precisely because it is high-volume, low-judgment,
and **loudly verifiable** (the build breaks or the golden diverges the moment
anyone slips) -- a safe place to find out whether junior devs help or just add
overhead. Your job is to **genuinely try to involve the juniors effectively**,
not to default to doing it all yourself or farming out only to peer Opus
sessions.

You have **full latitude** on method -- script-first then farm out
review/validation, juniors-do-prose-while-you-wire-the-solution, a `Workflow`
fan-out, or whatever you judge best. Mechanism in Claude Code: the `Agent`
tool takes a `model: "sonnet"|"haiku"` override; `Workflow` takes per-phase
overrides.

**Two required deliverables, equally weighted:**
1. A **clean rename** that passes the gate (above) with `git grep OspreySharp`
   == 0 in the agreed scope.
2. An **honest assessment / retro** for the dev manager: were the junior
   (Sonnet/Haiku) sessions helpful or a waste of time? Where did each tier add
   real value vs cost more (your time, tokens, or rework) than it saved? Which
   tasks suited a junior and which didn't? How did the orchestration feel, and
   what would you do differently? **Keep a running tally as you go** (task ->
   tier -> outcome) so the retro is grounded, not vibes. Put it in the Progress
   Log and surface it to Brendan at the end.

A useful prior, not a rule: pure find/replace is a *script's* job (free,
exact) -- spending junior tokens on what `-replace` does is itself a finding
worth reporting. Juniors tend to earn their keep on the judgment-y slices
(doc-prose rebrands, per-area cleanup against an acceptance test, a
second-pass verification sweep) -- but test that belief rather than assume it.

## Decisions (resolved 2026-06-27 by the dev manager)

1. **Historical records: PRESERVE.** Leave `todos/completed/`, memory, and
   other dated records as-is -- a dev going back through version-control
   history to the referenced commits will (correctly) still see "OspreySharp".
   Scope "complete removal" to **forward-facing / active** artifacts: pwiz
   source + projects + docs, and ai/ scripts + guides + skills + the
   path-based-skill hook + `MEMORY.md` + active todos.
2. **Cross-impl `Compare/*` scripts: RENAME now.** Replace the OspreySharp
   token in them as part of this sprint (cheap, mechanical). The separate
   parity-removal sprint (`project_osprey_parity_removal_sprint`) may still
   delete them later; don't conflate the two.
3. **TeamCity: Brendan handles.** Brendan will rename the TC configs/paths
   himself (Matt Chambers is the TC lead for any net-new config). Coordinate
   merge timing so CI isn't red between the path rename and the config update.
4. **Binary/assembly name: `Osprey` (PascalCase).** AssemblyName `Osprey` ->
   `Osprey.exe` / `dotnet Osprey.dll`; matches the brand and Skyline-style
   naming. Rust is retired, so the lowercase-`osprey` collision is moot.

## Known follow-ups after the rename lands

- The Mike Riffle email + its githack links (`pwiz_tools/OspreySharp/...`)
  go stale -- update to `pwiz_tools/Osprey/...` and `Osprey --task ...`.
- skyline.ms publishing of `CommandLine.html` / `Osprey-workflow.html`
  (separate TODO) should use the new paths.

## Progress Log

### 2026-06-27 - Planned; ready to run

Scope surveyed (~726 pwiz / ~1,776 ai occurrences). Confirmed the golden
carries no "OspreySharp", so a byte-identical rename is achievable in one
pwiz PR. All four decisions resolved by the dev manager (preserve history;
rename Compare/* now; Brendan owns the TeamCity rename; binary name
`Osprey`). Branch `Skyline/work/20260627_osprey_rename` created off master.
**Next session: `/pw-continue` and go** -- you are the dev lead; involve the
Sonnet/Haiku junior devs and deliver both the clean rename and the retro.

### 2026-06-27 - Executed; both repos green

**Result: rename complete, gate green, byte-output-neutral.**
- pwiz: 228 git renames + content sweep across ~211 files; exact-case
  `git grep OspreySharp` == 0. Build clean; 437 tests pass / 3 skipped / 0 fail
  (net8.0); ReSharper inspection 0 warnings / 0 errors on `Osprey.sln`;
  `regression.ps1 -Dataset Stellar` PASS all 3 modes (vs golden, HPC-chain==
  straight, resume==straight) -- blib 52,514,816 bytes, identical to golden.
  `CommandLine.html` regenerated by the self-healing test and committed.
- ai: 54 renames + content sweep across ~61 files (scripts/Osprey, guides,
  SKILL.md, both path-based hooks, TOC, STARTUP, one active TODO). Forward-facing
  exact-case == 0; only intentional historical refs (completed/backlog TODO
  filenames, a memory filename) remain by Decision 1.

**Method.** Opus did all consistency-critical structural work itself:
`git mv` (parent + 10 project folders + 10 csproj + sln + DotSettings), then a
deterministic EOL/BOM-preserving exact-case `OspreySharp`->`Osprey` sweep driven
by `git grep -l` (scope == rename scope, incl. the 9 cross-refs and every csproj
field/namespace/using). Exact-case was the key choice: every preserve-list token
(`OspreyTask`, `OSPREY_*`, `.osprey.task`) and every historical TODO/memory
filename ref uses a different casing, so they were auto-preserved with **no
skip-list**. Hand-fixed only the Jamfile lowercase build identifiers
(`OSPREY_SHARP_PATH`, `do_osprey_sharp`). Sweep scripts live in
`ai/.tmp/osprey-rename/`.

**Environment cost (the real surprise).** The biggest time sink was not tokens
or model tier -- it was a Windows directory lock blocking `git mv` of the parent
dir: a stray PowerShell console with cwd inside `pwiz_tools/OspreySharp`, plus VS
having the solution open, plus the C# LSP's `ReadDirectoryChangesW` watch (the
last is invisible to Restart Manager, which is why "no lockers reported"). Cost a
session restart with `csharp-lsp@pwiz-lsp` disabled. **Re-enable that plugin
(settings.json -> true) once this lands** -- it's off right now.

**Delegation tally (task -> tier -> outcome):**
- Structural moves (git mv) -> **Opus** -> clean, 0 rework. Not delegatable: one
  slip mis-wires the solution.
- Bulk token sweep (802 pwiz + 710 ai occurrences) -> **script (Opus authored)**
  -> exact, free, reviewable in the diff. Spending junior tokens here would have
  been pure waste -- the prior held.
- Jamfile build identifiers -> **Opus** -> small, judgment-y (build wiring).
- Prose review of 3 ai/ guides (osprey-development-guide, crossimpl, SKILL) ->
  **Sonnet** -> high value. Made 3 correct collapsed-distinction fixes, correctly
  judged SKILL.md already clean, AND flagged `debugging-principles.md` (outside
  its assigned files) -- a real miss I'd have shipped. ~49k tokens, ~0 rework.
- Final cross-repo verification audit -> **Haiku** -> earned its keep. Caught an
  all-caps `OSPREYSHARP` display string my exact-case sweep and my own greps both
  missed, and classified all case-variants correctly. A genuine independent miss.
- "Scan the *remaining* ai/ prose for collapses" -> **declined to delegate** ->
  a 1-line grep showed only 2-3 real spots, so a second junior would have been
  overhead. (Recording the non-delegation is itself a finding.)
- Flagship prose with positioning implications (Osprey-workflow.html title +
  Rust-vs-C# contrasts; README; the `GenerateUsageHtml()` intro that had become
  circular "Osprey is the C# implementation of Osprey") -> **Opus** -> kept tight
  control; reframed Osprey as MacCoss's DIA tool in C# with maccoss/osprey as the
  retired Rust prototype. Flag for dev-manager sanity check (positioning prose).

**Retro (honest):** For a *pure mechanical rename*, the script is the hero and
Opus is the wiring; juniors are NOT useful on the find/replace itself. Juniors
paid off exactly where the prior predicted -- **judgment review of swept prose**
(Sonnet) and **independent verification** (Haiku) -- and both caught real misses
a single Opus pass shipped. Net: the layered shape (exact-case script -> Sonnet
judgment pass -> Haiku audit) beat solo-Opus on quality at trivial token cost.
The honest caveat: orchestration overhead (writing precise briefs, classifying
findings) was real and only worth it because the verification surface was large;
on a small change I'd skip the juniors. One process gap: my "preserve any
osprey_sharp TODO-filename ref" instruction was right for pointers but wrong for
a *glob convention* in SKILL.md -- I fixed that edge case myself.

**Open / handoff:**
- Commit not yet made -- working tree staged-and-clean in both repos, awaiting
  dev-manager go for the pwiz PR + the direct ai-master commit.
- Brendan owns the TeamCity config/path rename (Decision 3); coordinate merge
  timing so CI isn't red between the path rename and the TC update.
- Re-enable `csharp-lsp@pwiz-lsp` after merge.
- Known follow-ups (Mike Riffle email githack links; skyline.ms publishing) per
  the section above, unchanged.

### 2026-06-27 - Merged

PR #4335 merged (squash) as commit 1ca152c5 on master; CI was 24/24 green. The
OspreySharp -> Osprey rename shipped end to end: `pwiz_tools/Osprey` (dir, sln,
ten projects, namespaces, AssemblyName -> `Osprey.exe`/`Osprey.dll`), the nine
cross-references, regenerated `CommandLine.html`, and byte-identical pipeline
output (regression golden unchanged; local Stellar + Astral and the TeamCity
Perf/Regression all PASS). ai/ tooling + docs renamed in coordinated ai-master
commits. Brendan updated the TeamCity Osprey configs to the new path. Deferred /
follow-up: `csharp-lsp@pwiz-lsp` left disabled (re-enable when next working in the
Osprey tree); two backlog TODOs filed (`osprey_redistribution`,
`vendor_reader_test_timeout`); coordinate the OspreySharp->Osprey rename with
Mike's in-flight `Noble-Lab/Carafe` integration (PRs #9/#10, which hardcode the
old path). Delegation retro (the co-equal deliverable) is in the prior entry.

