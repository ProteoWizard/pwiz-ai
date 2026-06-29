# TODO-release_process_unification.md

## Branch Information
- **Branch**: (to be created when work starts)
- **Base**: `master` (pwiz); ai/ changes direct to ai master
- **Created**: (pending)
- **Status**: Backlog (FIRST DRAFT for review)
- **PR**: (pending)
- **Objective**: Reconcile ProteoWizard/pwiz's ad hoc per-tool build-and-release
  flavors into ONE coherent release process that (1) produces a directly usable,
  *signed* installer for every shipped component, (2) auto-archives labeled
  releases at a coarser-than-every-commit cadence in a host that outlasts MacCoss
  lab infrastructure, and (3) folds Osprey in as a first-class member rather than
  a sixth bespoke story.

## Origin

Drafted from a design review with Brendan (2026-06-28) following the Osprey
redistribution work (pwiz PR #4336, which gave Osprey its first ZIP + WiX MSI).
The review's throughline: the per-tool installer/release stories have diverged,
and Osprey shouldn't add a sixth. This plan is the proposed convergence. It is
also intended as the artifact to take to Matt Chambers, who wants ProteoWizard
releases kept fully automatic (TeamCity-built) and archived somewhere with an
open-source longevity guarantee independent of MacCoss lab hosting.

## Problem: the current ad hoc flavors

| Component | Versioned (Jam scheme) | Signed | Labeled (tag / GH Release) | Durably archived | Primary download today |
|---|---|---|---|---|---|
| **pwiz core** (msconvert, `pwiz-bin` tar, `pwiz-setup.msi`) | yes `3.0.<YY><DDD>` | NO | NO | NO (TeamCity/AWS, ~5-10 builds) | latest "Core Windows x86_64" artifact on AWS |
| **Skyline** | yes `YY.N.B.DDD` | yes (ClickOnce + exe, manual, release machine) | yes (git tags) | yes (skyline.ms + tags) | skyline.ms (ClickOnce / ZIP / MSI), human-driven |
| **SkylineBatch / AutoQC** | yes | ClickOnce manifests only | with Skyline | with Skyline | ClickOnce; SkylineBatch ships inside Skyline |
| **BiblioSpec** | rides pwiz | NO | NO | partial (`BiblioSpec.zip` artifact + website page) | `BiblioSpec.zip` (built by SkylineTester) + in Skyline install |
| **Osprey** | yes `YY.N.B.DDD` | hook only (off) | NO | NO (TeamCity artifact) | none until PR #4336 |
| **TeamCity test builds (Skyline)** | yes | NO | NO | NO | exe buried in `SkylineTester.zip` (342 MB) |

Two structural gaps dominate: **signing is ClickOnce-only** (because ClickOnce is
the only artifact type browsers *force* signing on), and **durable, labeled,
citable archival is Skyline-only**. Everything else is "latest artifact, gone in
~10 commits," and the test build a collaborator is pointed to is buried inside
SkylineTester.zip.

What is already solved and should be built upon, not redone:
- **Unified, reproducible versioning.** `YY.N.B.DDD` (git-commit-date day-of-year)
  is centrally enforced in `Jamroot.jam` / `Jamfile.jam` across pwiz, Skyline,
  SkylineBatch, AutoQC, and Osprey (Matt implemented it under Brendan's
  direction). pwiz core keeps `3.0.<YY><DDD>` on the same DOY engine. Rebuilding a
  tag is bit-identical.
- **The `B` digit already encodes the channel** for the Skyline family
  (0=release, 1=daily, 9=feature-complete) -- the version is itself a routing key.
- **DigiCert KeyLocker is already in use** (cloud HSM, no local private key since
  the last renewal; cert expires 2026-02-28... see note). The signing primitive
  lives in `pwiz_tools/Skyline/SignAfterPublish.bat`:
  `signtool sign /csp "DigiCert Signing Manager KSP" /kc <key> /f <crt> /tr <ts> ...`
  plus `mage -update` for ClickOnce manifests. The KeyLocker auth + key alias
  live only on release machines today.

## Goals

1. **One directly-usable, signed installer per component**, discoverable (no
   digging inside SkylineTester.zip).
2. **Automatic, coarser-than-commit releases**: a scheduled promotion (proposed:
   monthly, day 1) of the latest green build to a labeled, archived release --
   fully automatic (Matt's requirement), no human in the loop for the routine case.
3. **Longevity independent of MacCoss hosting**: archive in GitHub Releases
   (primary), mirror to SourceForge Files (already a pwiz download host that keeps
   history), and mint Zenodo DOIs for major/citation-grade releases.
4. **Sign everything in CI** -- native and managed, exe / MSI / ClickOnce -- via
   one shared primitive, with timestamped signatures so archived releases stay
   verifiable after cert expiry.
5. **Fold Osprey + BiblioSpec + pwiz core into the same model** so all six
   deliverables behave identically.

## Target model

### Two tiers, uniform across every component

**Tier C -- Continuous / "testing"** (per-commit, TeamCity + AWS, short
retention): every component emits a *directly runnable* installer. This is the
"unofficial testing release" a collaborator is pointed to before an official
release. Unsigned (so it is visibly unofficial -- see "Officialness").

**Tier M -- Monthly / "release + archive"** (scheduled, automatic, day 1 of
month): a TeamCity job promotes the latest green master build of each component to
a **GitHub Release** (tag + signed assets), which becomes the primary download the
websites point at and the durable archive. "Monthly" is the cadence/trigger, not a
bundle.

### Component matrix

| Component | Tier C (testing artifacts) | Tier M (monthly -> signed GitHub Release) |
|---|---|---|
| **pwiz core** | `pwiz-bin` tar + `pwiz-setup.msi` (exist) | promote + sign -> GH Release; proteowizard.org / SourceForge point here |
| **BiblioSpec** | `BiblioSpec.zip` (exists) | promote + sign -> GH Release |
| **Skyline-daily** | NEW `Skyline-daily-<ver>.zip` + `.msi` as first-class artifacts; keep `SkylineTester.zip` + `SkylineNightly.zip` for their real jobs | monthly signed Skyline-daily snapshot -> GH Release (additive; majors stay human-driven, also -> GH) |
| **SkylineBatch / AutoQC** | installer artifacts | optional monthly archive; primary install stays ClickOnce |
| **Osprey** | `Osprey-<ver>.zip` + `.msi` (PR #4336) | promote + sign -> GH Release; canonical artifact for Carafe |

Early cheap win, independent of everything else: add `Skyline-daily-<ver>.zip` /
`.msi` as top-level artifacts in the "Skyline master and PRs" config and point
collaborators there, so `SkylineTester.zip` goes back to being only a test-suite
runner.

### Officialness = the signature (the linchpin for promote-don't-rebuild)

"Promote, don't rebuild" only works if **nothing in the compiled binary asserts
"official vs not."** Today Skyline bakes that distinction in (`--official` / the
"automated build" string in Help > About and `--version`), so a promoted test
build would self-report as not-official. Resolution:

- **Stop expressing "official" at compile time.** Retire the `--official` /
  "automated build" self-assertion.
- **Express it as the signature, applied at promote time.** Authenticode is a blob
  appended to an already-built exe/MSI -- no recompile -- so "promote + sign" ships
  the exact tested code with the signature as the only (and the meaningful) delta.
  - Tier C: unsigned -> visibly unofficial.
  - Tier M: signed with the MacCoss Lab cert -> official.
- **Help > About and `--version` derive the label from the binary's own signature
  at runtime** ("Official release -- signed by University of Washington (MacCoss
  Lab)" vs "Unofficial build (unsigned)"). This also makes posted error reports
  self-identify as official-or-not (a win for exceptions triage).

Consequences:
- **"Code-identical," not "byte-identical"** (signature is embedded); provenance is
  the tag/commit, guaranteed reproducible by the DOY scheme.
- **Skyline majors remain a deliberate human rebuild** -- a major is a genuinely
  different binary identity (`B=0`, product name "Skyline" not "Skyline-daily",
  release icon). That is outside the promote lane by design, and correct. Rule:
  the version line and product identity are the only legitimate *build-time*
  differences; "official vs not" is never a build-time difference.
- **Windows-only.** Authenticode does not apply to Osprey's `linux-x64` artifact;
  there officialness rests on the GitHub-Release placement + version, optionally
  hardened with a detached GPG / sigstore signature on the artifact.

### Signing tenet

**Every release artifact is signed in CI with the timestamped MacCoss Lab cert --
native and managed, exe and MSI and ClickOnce -- via one shared
`Sign-WithKeyLocker` primitive; the signature is both the trust mechanism and the
definition of "official."**

- Extract the file-signing line from `SignAfterPublish.bat` into a reusable
  `Sign-WithKeyLocker.ps1` (signtool + "DigiCert Signing Manager KSP" + key alias +
  `.crt`, timestamped). ClickOnce keeps its extra `mage` steps on top.
- pwiz core / BiblioSpec are native C++ built by bjam with no `AfterPublish` hook,
  so their signing is naturally a **TeamCity post-build step** over the output --
  the purest case for CI signing.
- **Scope**: sign our own built exes/DLLs + the installer (MSI / ZIP). Leave
  vendor DLLs (Thermo, Bruker, etc.) alone -- already vendor-signed. For an MSI,
  two passes: sign contents, then sign the `.msi`.
- **Timestamping = longevity**: `/tr http://timestamp.digicert.com` keeps a
  signature valid after the cert expires, so archived releases stay verifiable for
  years. Signing and the archival goal are the same lever.
- **Security posture decision** (below): putting KeyLocker auth on a shared
  TeamCity agent lets it sign anything unattended.

### Versioning note (one drift risk to fix)

Osprey is the only family member with TWO version computations: `Osprey/Jamfile.jam`
(if built via bjam) and the PowerShell `version.ps1` / `build.ps1` (the actual CI
path via `tcbuild.bat`). They mirror the same constants but are a second source of
truth. Fix as part of this work: confirm whether `Osprey/Jamfile.jam` is exercised
at all; then either delete it and let `version.ps1` be the source, or add a
verifier asserting the .NET-stamped `OspreyVersion.Current` equals the Jam-derived
version.

## Archival / longevity (layers)

- **GitHub Releases** (primary, dev-facing, per-component prefixed tags on the
  `ProteoWizard/pwiz` repo: `pwiz-3.0.26178`, `Skyline-daily-26.1.1.178`,
  `Osprey-26.1.1.178`, `bibliospec-...`). Outlasts MacCoss hosting; stable URLs;
  handles the binary sizes (<2 GB/asset; largest today ~92 MB).
- **SourceForge Files mirror** (already own `proteowizard.sourceforge.net`; SF
  keeps every historical release by default) -- a second non-MacCoss archive for
  near-free.
- **Zenodo DOI** for major / yearly releases -- CERN-backed, citation-grade,
  independent of GitHub. The identifier a methods section actually cites.

## Website re-pointing

- proteowizard.org / proteowizard.sourceforge.net: install the **monthly GitHub
  Release** assets, not the latest TeamCity/AWS artifact. (pwiz can keep building
  on TeamCity/AWS exactly as now; a propagation step copies/promotes the monthly
  pick to the GitHub Release + SF mirror.)
- skyline.ms download pages: continue to host or point at the GitHub Release;
  GitHub becomes the archive of record either way.

## Key design decisions (recommendations, for review)

1. **Per-component GitHub Releases (prefixed tags), NOT a monthly umbrella.**
   Best serves individual citation ("the exact pwiz version in this paper").
2. **Promote the tested artifacts; do not rebuild for the monthly.** Sign at
   promote. (Majors are the explicit human-rebuild exception.)
3. **Monthly is additive to Skyline's existing process**, not a replacement.
   Monthly auto-release graduates pwiz / Osprey / BiblioSpec (no discipline today)
   and adds a GitHub archive for Skyline-daily; Skyline majors keep their workflow
   but also emit a GitHub Release via the same primitive.
4. **Longevity layers**: GitHub primary + SourceForge mirror + Zenodo for majors.
5. **CI signing posture**: unattended for Tier C/monthly per-commit components;
   consider a gated/approval workflow in KeyLocker for the official Skyline major.

## Proposed rollout (phased)

**Phase 0 -- decisions.** Confirm the five decisions above + the signing posture.

**Phase 1 -- CI signing keystone (pilot on Osprey + one native target).**
- Provision one TeamCity agent with the DigiCert KeyLocker KSP + `SM_*` auth as
  TeamCity secret params + key alias + `.crt`.
- Extract `Sign-WithKeyLocker.ps1`; reconcile Osprey `package.ps1 -Sign` to it
  (currently uses generic `signtool /a` -- wrong for KeyLocker).
- Prove it signs both a managed artifact (Osprey MSI/exe) and a native one (a
  BiblioSpec exe). This validates the pattern for the whole fleet.

**Phase 2 -- "official = signature" runtime readout.**
- Add Help > About / `--version` signature readout (Skyline + Osprey).
- Retire Skyline's `--official` / "automated build" self-assertion.

**Phase 3 -- monthly release pipeline (pilot on Osprey end-to-end).**
- Scheduled day-1 TeamCity job: pick latest green -> tag -> sign -> create GitHub
  Release + upload assets -> (optional) SF mirror. Osprey first (new, low stakes,
  already has zip+msi), then template to the rest.

**Phase 4 -- roll to pwiz core + BiblioSpec.**
- Sign in CI; propagate the monthly pick to GitHub Release + SF; re-point
  proteowizard.org / SourceForge to the GitHub Release.

**Phase 5 -- Skyline + SkylineBatch/AutoQC.**
- Skyline-daily first-class artifacts + monthly GitHub archive; move ClickOnce/MSI
  signing onto the shared primitive; majors emit GitHub Releases too.

**Phase 6 -- citation hardening.**
- Zenodo DOI integration for majors; Singularity `.sif` as a release asset for the
  Docker/HPC channel; consider cosign for container images.

## Open questions / coordination

- **Cert renewal**: the doc references a DigiCert cert expiring 2026-02-28; confirm
  the exact date and renewal plan (timestamping protects already-signed archives
  regardless).
- **KeyLocker for CI**: is the credential per-release-machine or one account
  credential that can be scoped onto a TeamCity agent?
- **Matt**: agreement on monthly cadence, GitHub-as-archive, demoting AWS/commit
  builds to "unofficial testing," and propagating pwiz to the monthly release point.
- **Docker**: confirm DockerHub retention concerns; decide ghcr.io mirror +
  Singularity-as-release-asset.
- **Cadence**: monthly day-1 confirmed, or a different period?

## Non-goals / out of scope

- Changing the version scheme (already unified and owned).
- Replacing Skyline's human-driven major/patch release process (it stays; it just
  also emits GitHub Releases).
- Bundling Osprey inside the Skyline installer (separate Osprey-redistribution
  Phase 4; this plan only makes the artifacts coherent and signed).

## References

- `ai/docs/release-guide.md` -- Skyline release process (the gold standard to
  generalize), version scheme, publish paths, Docker/DockerHub deploy.
- `pwiz_tools/Skyline/SignAfterPublish.bat` -- the KeyLocker signing primitive
  (`signtool` + "DigiCert Signing Manager KSP"; `mage` for manifests).
- `Jamroot.jam` / `Jamfile.jam` -- centrally enforced `YY.N.B.DDD` DOY versioning.
- pwiz PR #4335 (OspreySharp -> Osprey rename), PR #4336 (Osprey ZIP + WiX MSI;
  `pwiz_tools/Osprey/package.ps1`, `Installer/Osprey.wxs`, `tcpackage.bat`).
- TeamCity artifacts observed (2026-06-28): "Core Windows x86_64" ->
  `pwiz-bin-...tar.bz2` + `pwiz-setup-3.0.26178...msi` + `VERSION`; "Skyline master
  and PRs" -> `BiblioSpec.zip` + `SkylineNightly.zip` + `SkylineTester.zip`.
- `ai/.tmp/osprey-carafe-adoption-plan.md` -- the related Carafe handoff.
