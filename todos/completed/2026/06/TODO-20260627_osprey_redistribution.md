# TODO-20260627_osprey_redistribution.md

## Branch Information
- **Branch**: `Skyline/work/20260627_osprey_redistribution`
- **Base**: `master` (pwiz); ai/ changes direct to ai master
- **Created**: 2026-06-27
- **Status**: Completed
- **PR**: [#4336](https://github.com/ProteoWizard/pwiz/pull/4336) (merged 2026-06-29 as 9e2ffb07f2)
- **Depends on**: the OspreySharp -> Osprey rename (pwiz PR #4335) landing first. DONE -- #4335 is on master (commit 1ca152c549); pwiz_tools/Osprey exists.

## Session scope (2026-06-27 night session, confirmed with Brendan)
This session implements **Phase 2 (standalone ZIP) + Phase 3 (WiX MSI) + TeamCity
artifact wiring**. Phase 4 (bundle inside Skyline) is DEFERRED to a follow-up PR
(Skyline is net472, Osprey net8.0 -> can't share a runtime -> forces a ~150MB
self-contained copy + WiX-template edits inside Skyline = too much CI risk for one
PR). Phase 5 (website) and Phase 6 (UI) remain future. Decisions taken:
- Platforms v1: Windows + Linux (`Osprey-<ver>-win-x64.zip`, `...-linux-x64.zip`); MSI = win-x64.
- Distribution runtime: net8.0 only, self-contained (no system .NET dependency).
- MSI: per-machine `C:\Program Files\Osprey`, Add/Remove-Programs entry.
- Signing: unsigned draft + env-gated signtool hook (off by default), documented.
- TeamCity: build/package emits artifacts to a known dist path; server-side
  artifact-path change documented for Brendan (can't edit server config from repo).
- Packaging lives in a standalone `package.ps1` (NOT wired into Boost.Build/pwiz-bin);
  Osprey is its own .NET tool with its own sln / TC configs / versioning.
- **Objective**: Give Osprey first-class redistribution: (1) a stand-alone download posted on skyline.ms, (2) a complete copy shipped inside the Skyline installation, and (3) groundwork toward running Osprey from the Skyline UI as the default DIA search engine. Near-term driver: replace EncyclopeDIA with Osprey on the skyline.ms home page, which requires a stand-alone Osprey install + a landing page. The ZIP/`.msi` this sprint produces should become the **canonical Osprey artifact** that downstream tools (e.g. Carafe) consume, replacing per-tool home-grown OspreySharp builds.

### 2026-06-29 - Merged

PR #4336 merged as commit 9e2ffb07f2. Shipped Phase 2 (self-contained net8.0
ZIPs win-x64 + linux-x64) + Phase 3 (per-machine WiX v5 .msi) + version.ps1 +
the per-commit "Osprey Windows .NET" config publishing the unsigned installers
as Tier-C artifacts (tcbuild.bat self-provisions wix). Installers are UNSIGNED;
CI signing, the monthly GitHub release, Phase 4 (Skyline bundling), Phase 5
(website/landing page) and Phase 6 (UI) are deferred -- see
TODO-release_process_unification for the broader release-coherence plan.
Next priority: hand Mike the Osprey artifacts for Carafe adoption
(ai/.tmp/osprey-carafe-adoption-plan.md) to replace his ad hoc OspreySharp
installer build. The Osprey regression did not re-run on the final CI-plumbing
commit but passed on the code-complete commit 8e04ae8bfb (since-diffs are
tcbuild.bat only, output-neutral).

## What we ship vs. what we build (TFM x platform)

"net472", "net8.0", and "linux" are NOT three parallel installs -- they are two
axes plus a self-contained/framework-dependent knob:
- Runtime / TFM: net472 (.NET Framework, **Windows-only**) vs net8.0 (cross-platform).
- Platform / RID: win-x64 vs linux-x64. (.NET Framework is Windows-only, so
  net472 x Linux does not exist.)

DISTRIBUTED (package.ps1): **net8.0 only, self-contained, two platforms**:
- `Osprey-<ver>-win-x64.zip` + `.msi`   (net8.0 self-contained)
- `Osprey-<ver>-linux-x64.zip`          (net8.0 self-contained)
Self-contained means the .NET 8 runtime is bundled **inside** each artifact
(~80 MB unpacked), so the user installs nothing else -- there is no separate
"install .NET 8" step; the artifact IS Osprey + its runtime.

BUILT/TESTED BUT NOT DISTRIBUTED: **net472**. It is a parity/test target (matches
the Rust reference at 1e-9) but is NOT canonical -- it differs from net8.0
byte-wise in cosmetic CLR float formatting. net8.0 is the canonical gated runtime.
Shipping net8.0-self-contained-only keeps numerics canonical, stays cross-platform,
and removes any "is the right runtime installed?" question. (A net472
framework-dependent Windows build is possible and would be smaller -- .NET
Framework is in-box on Windows -- but trades away canonical numerics +
cross-platform; not worth it.)

Skyline-bundling (Phase 4) note: Osprey's net472 target does NOT enable in-process
hosting by Skyline (also net472). Osprey is an out-of-process EXE, and a net472
process cannot load net8.0 in-process regardless. Bundling Osprey in Skyline =
dropping the self-contained net8.0 build into the install tree (a second runtime
alongside Skyline's), which is why Phase 4 carries the ~150 MB cost.

## Session log (2026-06-27 night)

Delivered in pwiz PR **#4336** (branch `Skyline/work/20260627_osprey_redistribution`):
- `pwiz_tools/Osprey/package.ps1` -- per-RID self-contained net8.0 ZIPs
  (win-x64 + linux-x64), single versioned top folder, docs/README/LICENSE
  bundled, pdbs stripped, in-bundle CommandLine.html link rewritten to local;
  `-Msi` builds the WiX v5 per-machine installer; env-gated `-Sign` hook.
- `pwiz_tools/Osprey/version.ps1` -- shared version formula; `build.ps1` now
  dot-sources it (DRY: binary stamp == artifact name).
- `pwiz_tools/Osprey/Installer/Osprey.wxs` -- WiX v5 installer (Program Files,
  PATH, ARP). WiX v5 chosen because v6/v7 require the paid OSMF EULA.
- `pwiz_tools/Osprey/tcpackage.bat` -- TeamCity packaging entry point.
- README "Redistribution" section; `.gitignore` ignores `dist/`.

Local verification: both zips + msi built; win zip exe runs `--help`; msi
validated via Installer DB (per-machine, 219 files, PATH, v26.1.178) and
`msiexec /a` admin-extract (-> Program Files\Osprey\Osprey.exe). Scripts parse
clean. No C# touched.

TeamCity GREEN on final head 8e04ae8bfb: per-commit build 4068111 (build +
tests + coverage) SUCCESS; regression 4068112 (Stellar + Astral byte-identical)
SUCCESS. Self-review (fresh-context Sonnet) findings addressed in commit
8e04ae8bfb (version.ps1 -RepoPath mandatory; package.ps1 -Encoding utf8; wxs
Files win-only note).

2026-06-29: wired the per-commit "Osprey Windows .NET" config to publish the
unsigned installers as Tier-C testing artifacts. tcbuild.bat now runs package.ps1
after build+test (publishArtifacts service messages -> win-x64 ZIP + .msi; no
server-side artifact-path config needed) and self-provisions the wix v5 tool +
v5 UI extension if the agent lacks them. Verified GREEN: build 4068695 (#142, head
8c13bd2191) publishes Osprey-26.1.1.180-win-x64.zip + .msi. NOTE: keep the wix
self-provision (dotnet global tools are per-user, so a manual install only helps
if the agent service runs as that user); revert only if agents are provisioned
explicitly. Signing is a later CI phase (see TODO-release_process_unification).

**TO WIRE UP (server-side, Brendan):**
1. Create a TeamCity build config "Osprey Package" (or add a build step) that
   runs `pwiz_tools/Osprey/tcpackage.bat`, triggered on master and/or release
   tags. Artifacts self-publish via `##teamcity[publishArtifacts]` -- NO
   artifact-path config needed. Agent prereq: the WiX v5 dotnet tool +
   `WixToolset.UI.wixext/5.0.2` (commands in tcpackage.bat header).
2. Code signing: supply a cert, then run packaging with `-Sign` (or set
   `OSPREY_SIGN*`); script hard-fails if signing is requested but unavailable.

**Open follow-ups:** Phase 4 (Skyline bundling), Phase 5 (skyline.ms landing
page + doc hosting + branding), Phase 6 (UI). Carafe adoption plan written to
`ai/.tmp/osprey-carafe-adoption-plan.md` (retarget Mike's PRs #9/#10 at the
official artifact + fix hardcoded OspreySharp names).

NOTE: the ai/ TODO move commit is LOCAL only this session (classifier blocked
the push to ai master); push `git -C C:\proj\ai push origin master` in the AM.

## Background / motivation

Osprey is the C# DIA search tool in `pwiz_tools/Osprey` (just renamed from
OspreySharp, PR #4335). It is a **command-line tool with no UI**, multi-targeted
`net472;net8.0`, x64, producing `Osprey.exe` / `Osprey.dll`. net8.0 is the
canonical runtime; it also runs on Linux (HPC).

Two pressures converged:
- Mike has started adding OspreySharp to **`Noble-Lab/Carafe`** (open PRs from his
  `maccoss` fork; see Reference models) -- "High quality in silico spectral
  library generation for DIA proteomics." It builds its own OspreySharp-bundled
  `.msi`, and its commit messages say "OspreySharp," which is part of what
  motivated finishing the rename.
- We want Osprey to be distributable the way Skyline's other companion tools are,
  rather than an internal build artifact -- and to be the single official build
  that downstream tools reuse.

**Current state of Osprey distribution = nothing.** `pwiz_tools/Osprey/build.ps1`
explicitly "publishes NO downloadable artifacts"; the TeamCity config only
publishes the raw `bin/.../net8.0` + `net472` dirs and TestResults. Osprey is
**not** bundled into the Skyline install and is **not** on the website.

## Target end-states

1. **Stand-alone download** on skyline.ms, modeled on BiblioSpec -- a CLI engine
   that runs separately on Windows/Linux. (NOT a ClickOnce installer like
   SkylineBatch: Osprey has no UI.)
2. **Shipped inside the Skyline installation**, like BiblioSpec, so a Skyline user
   already has Osprey on disk.
3. **Canonical for downstream consumers** -- the official ZIP/`.msi` supersedes
   home-grown per-tool OspreySharp builds (Carafe today; others later), which
   point at / bundle the official artifact instead of building from the pwiz tree.
4. **(Future, separate sprint)** Osprey driven from the **Skyline UI** as a DIA
   search engine, eventually the **default** (replacing EncyclopeDIA's role),
   requiring no extra install. Months out; flagged so 1-3 don't paint us into a
   corner.

## Package format (DECIDED 2026-06-27)

Primary deliverable: a **versioned-folder ZIP** of a self-contained .NET publish.
Second deliverable (fast-follow): a **WiX `.msi`**. Per-RID artifacts; the
generated docs are bundled inside the zip. (Decided with Brendan; do not
re-litigate -- just implement.) Independently corroborated by Mike's Carafe build,
which bundles OspreySharp as a self-contained per-RID `dotnet publish` (see
Reference models).

ZIP layout -- ONE containing folder, never root-exploded (a self-contained
publish is `Osprey.exe` + dozens of runtime/dependency DLLs, so dumping them at
the zip root explodes ~100 files into the user's extract dir):

    Osprey-<version>-win-x64.zip
    +- Osprey-<version>-win-x64/        (single top-level folder)
       +- Osprey.exe                    (at the folder root; easy to find / add to PATH)
       +- *.dll                         (bundled .NET runtime + Arrow / Parquet / Zstd / ...)
       +- Documentation/                (CommandLine.html + Osprey-workflow.html)
       +- README / LICENSE

Why this layout:
- **Side-by-side for free** -- each version unzips to its own `Osprey-<version>`
  folder, so multiple versions coexist. Critical for HPC reproducibility: pin an
  exact Osprey per analysis, copy the folder to a cluster, run it with ZERO
  system-.NET dependency (self-contained).
- **Self-documenting** -- the generated `CommandLine.html` /
  `Osprey-workflow.html` ride along in the zip (the same files the landing page
  iframes).
- **Clean extraction** -- mirrors Skyline's "unzip -> one folder -> double-click
  the exe" UX; no Downloads-folder explosion.
- **Per-platform zips** (`...-win-x64.zip`, `...-linux-x64.zip`), one top-level
  folder each. Do NOT mix RIDs in one zip.

Single-file publish (`PublishSingleFile`) is an OPTIONAL later refinement (fewer
files) -- but Osprey's native deps (Parquet / Zstd / IronCompress) do not all
embed cleanly and it adds first-run extraction latency, so the versioned folder
stays primary.

`.msi` (WiX, fast-follow): packages the SAME self-contained publish into a signed
`C:\Program Files\Osprey` install (per-machine) with an Add/Remove-Programs entry
-- for pharma IT and centrally-deployed / virtualized academic environments (the
same reason Skyline eventually shipped an `.msi`). ZIP is the historical-record
format (most reliably archived, like Skyline's releases); the `.msi` is the
presentable institutional installer, and the canonical one downstream tools adopt.

## Branding / design (in progress, parallel track)

Brendan is working with a designer; a home-page mock-up already exists (captured
this session):
- A finished **Osprey logo** -- an osprey diving over a blue Skyline-style
  cityscape, matching Skyline's blue identity -- placed in EncyclopeDIA's slot.
- The **BiblioSpec** logo is being recolored from green to the same blue scheme.
- A new home-page layout swapping the EncyclopeDIA callout for Osprey.

Still needed: the **Osprey home-page blurb** (the mock-up reuses EncyclopeDIA's
placeholder text) and final logo asset hand-off. This track feeds Phase 5 but is
not blocking on the engineering (package + bundle) work.

## Reference models (study these first)

- **BiblioSpec** (`pwiz_tools/BiblioSpec`) -- the closest analog: an open-source
  CLI engine that ships *inside* Skyline AND runs stand-alone on Windows/Linux,
  with a project page + download on skyline.ms
  (https://skyline.ms/home/software/BiblioSpec/project-begin.view). Built via
  Boost.Build (`Jamfile.jam`); its binaries travel in the ProteoWizard release.
  Determine exactly how its stand-alone download is produced and how it lands in
  the Skyline install -- and use its landing page as the template for Osprey's.
- **SkylineBatch** (`pwiz_tools/Skyline/Executables/SkylineBatch`) -- has a
  stand-alone download/website page too
  (https://skyline.ms/home/software/Skyline/wiki-page.view?name=skyline-batch),
  but it is **ClickOnce** because it has a UI. Use it as the model for the
  *website/standalone* pattern, NOT the installer mechanism. (Skyline itself ships
  as a ClickOnce installer *inside a ZIP*, and its side-by-side layout also lets
  you just unzip and double-click `Skyline.exe` -- the versioned-folder ZIP above
  gives Osprey the same unzip-and-run behavior without ClickOnce.)
- **Noble-Lab/Carafe** (GitHub; Java/Maven tool, NOT .NET) -- the most direct
  `.msi` prior art. Mike's OspreySharp work is in OPEN PRs from his `maccoss`
  fork: **PR #9** (`feature/ospreysharp-integration` -- `OspreyBlibReader` reads
  Osprey `.blib`, Koina library generation, `resolveOspreyBinary`) and **PR #10**
  (`ci/ospreysharp-installer` -- the MSI). **Cloned to `C:\proj\Carafe`; PR
  branches fetched locally as `pr-9-integration` and `pr-10-msi`.** How its MSI
  works (`scripts/generate_installer_win.bat`, `.github/workflows/build-installer.yml`):
  `jpackage --type msi` (WiX 3.x backend), **per-user** install to
  `%LOCALAPPDATA%\Carafe\app\`, bundling a **self-contained per-RID** OspreySharp
  publish (`scripts/build_ospreysharp.sh`: `dotnet publish -c Release -f net8.0
  -r <rid> --self-contained`; win-x64 / linux-x64 / osx-arm64). Takeaways:
  - Confirms our self-contained-per-RID decision.
  - jpackage is **Java-specific**; our pure-.NET `.msi` uses **WiX directly**.
    Carafe is the reference for layout / branding / vendor, and the per-user vs
    per-machine choice (Mike chose per-user; we want a Program Files option).
  - **Goal: replace Carafe's home-grown OspreySharp `.msi` with the official one
    from this sprint** -- Carafe consumes the official Osprey artifact instead of
    `build_ospreysharp.sh`. Its scripts also hardcode the old
    `pwiz_tools/OspreySharp` path + `OspreySharp.exe`, which break on our rename
    anyway -- coordinate with Mike to retarget PRs #9/#10 at the official build.
- **How Skyline bundles CLI tools**: `Skyline.csproj` pulls external executables
  in as `<Content Include>` items that copy into the Skyline output/install (e.g.
  `msconvert.exe` is linked in from `Shared/ProteowizardWrapper/obj/$(Platform)`;
  BiblioSpec's `modifications.xml` is Content). This is the likely mechanism for
  bundling `Osprey.exe` + its runtime into Skyline.
- **skyline.ms home page** (live): tools are shown as a callout = logo +
  `[Project]` link + short description + (for BiblioSpec) a download. EncyclopeDIA
  is the open-source DIA *search* engine slot -- the one Osprey replaces near-term.

## The Osprey landing page (Phase 5 target, spelled out)

Model it on BiblioSpec's project page. It should host the docs we already
generate, plus downloads:
- A **documentation view** with an `<iframe>` embedding
  `pwiz_tools/Osprey/Documentation/Help/en/CommandLine.html` (the CLI usage page,
  auto-generated + drift-locked by `TestCommandLineHelpDocumentation`).
- A **workflow/overview page** built from some form of
  `pwiz_tools/Osprey/Osprey-workflow.html` (the pipeline diagram).
- **Download + install links** for the ZIP (per platform) and the `.msi`.

Implication: both HTML docs must be **web-hostable**. They are already generated
in-repo (and currently cross-link via `raw.githack.com/.../pwiz_tools/Osprey/...`).
The sprint must decide where the website pulls them from (githack against
master, a copy published to skyline.ms, or an artifact) and keep that link target
correct after the rename.

## Proposed phases

### Phase 1 -- Reference gathering
- Carafe is already cloned (`C:\proj\Carafe`, branches `pr-9-integration` /
  `pr-10-msi`). Read `scripts/generate_installer_win.bat`,
  `scripts/build_ospreysharp.sh`, `.github/workflows/build-installer.yml` for the
  MSI/bundling approach.
- Document BiblioSpec's stand-alone build + how it reaches the Skyline install +
  how its skyline.ms landing page is wired.
- Skim SkylineBatch's ClickOnce setup only enough to confirm we are NOT copying it.

### Phase 2 -- Stand-alone Osprey ZIP (primary deliverable)
- Add a package target (extend `pwiz_tools/Osprey/build.ps1` or the Jamfile) that:
  - runs `dotnet publish -c Release -r win-x64 --self-contained` (and `linux-x64`),
  - copies the generated `Documentation/` (CommandLine.html, Osprey-workflow.html)
    + README/LICENSE into the publish dir,
  - zips it under the single versioned top-level folder per the layout above,
    naming `Osprey-<version>-<rid>.zip`.
- Add/adjust a TeamCity config to **publish** that zip artifact (today the Osprey
  config publishes none -- and watch the 4 GB per-artifact limit note in
  build.ps1).

### Phase 3 -- Osprey `.msi` (fast-follow, becomes the canonical installer)
- WiX installer that packages the same self-contained publish into
  `C:\Program Files\Osprey` (per-machine; pharma-IT-presentable), with
  Add/Remove-Programs entry; consider PATH entry and code signing.
- **Intent: this is the canonical Osprey `.msi`** that downstream consumers
  (Carafe today, others later) bundle/point at, replacing home-grown per-tool
  OspreySharp builds. Coordinate with Mike to retarget Carafe PRs #9/#10 at the
  official artifact (their scripts reference the old `OspreySharp` path/exe).

### Phase 4 -- Bundle Osprey inside Skyline
- Stage `Osprey.exe` + required runtime/DLLs into the Skyline install (via
  `Skyline.csproj` `<Content>` or the Skyline build staging), choosing a subdir
  (e.g. a `Tools/Osprey` or alongside the other bundled exes).
- Decide self-contained vs framework-dependent here (Skyline already targets a
  specific .NET; avoid shipping a second full runtime if Skyline's covers it).
- Mind install footprint/size and the existing Skyline installer.

### Phase 5 -- skyline.ms website
- Create the **Osprey project/landing page** (LabKey wiki, modeled on BiblioSpec's
  `project-begin.view`) with the iframe doc view + workflow page + download/install
  links described in "The Osprey landing page" section above. (Use the
  skyline-wiki skill / MCP.)
- Land the **Osprey logo** + recolored **BiblioSpec** logo from the designer.
- Write the **Osprey home-page blurb** and update the home page to replace the
  EncyclopeDIA callout with Osprey. Coordinate with whoever owns the home page.

### Phase 6 (future, separate sprint) -- Skyline UI integration
- Wire Osprey in as a DIA search engine reachable from the Skyline UI (compare to
  how EncyclopeDIA is wired: `EncyclopeDiaSearchDlg`, `EncyclopeDiaHelpers.cs`,
  the DDA/DIA search plumbing in `Model/DdaSearch`). Eventually make Osprey the
  default. Out of scope for this sprint; listed so earlier phases stay compatible.

## Open decisions (need Brendan's input early)
- **Platforms** for the stand-alone: Windows-only first, or Windows + Linux
  shipped together (Osprey supports Linux / HPC)? (Layout already supports both
  via per-RID zips; question is what we publish in v1.)
- **Runtime when bundled in Skyline**: reuse Skyline's .NET runtime
  (framework-dependent, smaller) vs ship Osprey self-contained inside Skyline too.
  (The stand-alone ZIP/`.msi` are self-contained either way.)
- **net8.0 only** for distribution, or keep net472 in the package?
- **Where Osprey lives** inside the Skyline install tree.
- **`.msi` install scope**: per-machine (Program Files; our stated goal) vs
  Mike's per-user choice in Carafe.
- **Doc hosting** for the landing-page iframes: raw.githack against master, a copy
  published to skyline.ms, or a build artifact?
- **Relationship to the ProteoWizard release** (BiblioSpec ships in pwiz-bin; does
  Osprey too, or as its own thing?).
- **Code signing** for the `.msi` (and exe) -- which cert / process.

## Constraints / gates
- C# work follows Skyline conventions (NO async/await, resource strings for any UI
  text, CRLF, etc. -- see ai/CRITICAL-RULES.md). Osprey itself is gated by its
  standing correctness (regression.ps1) + perf gates; a packaging change must keep
  output byte-identical and not perturb the build/tests.
- Cross-platform: don't Windows-only-ify Osprey; it runs on Linux.
- Coordinate website + Skyline-installer changes with their owners; the home-page
  swap is user-facing. Coordinate the Carafe handoff with Mike.

## References
- Rename that preceded this: pwiz PR #4335 (OspreySharp -> Osprey).
- `pwiz_tools/Osprey/` (build.ps1, tcbuild.bat, Directory.Build.props, README.md,
  Documentation/Help/en/CommandLine.html, Osprey-workflow.html).
- `pwiz_tools/BiblioSpec/` (Jamfile.jam) and skyline.ms BiblioSpec project page.
- `pwiz_tools/Skyline/Executables/SkylineBatch/` (ClickOnce -- contrast only).
- `pwiz_tools/Skyline/Skyline.csproj` (`<Content>` bundling of msconvert /
  BiblioSpec assets; EncyclopeDIA UI wiring at `EncyclopeDiaSearchDlg` /
  `Model/Lib/EncyclopeDiaHelpers.cs`).
- `C:\proj\Carafe` (clone; branches `pr-9-integration`, `pr-10-msi`) -- Mike's
  OspreySharp integration + jpackage MSI; `scripts/generate_installer_win.bat`,
  `scripts/build_ospreysharp.sh`, `.github/workflows/build-installer.yml`.
