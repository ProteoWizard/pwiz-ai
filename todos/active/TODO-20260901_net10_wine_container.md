# Build a net10 Wine container for the Windows-only vendor readers

## Branch Information
- **Checkout**: container work in `C:\dev\container`; pwiz-sharp work in `C:\dev\pwiz-msconvert-pr`
  (the original investigation ran from `C:\dev\pwiz-net8`)
- **Branch**: `Skyline/work/20260902_wine11_net10` (container) / `msconvert-parity` (pwiz)
- **Base**: `master` for the container repo; pwiz-sharp work sits on `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-01
- **Status**: container built and green offline. The pwiz payload is now the vendor-bundled
  installer (Skyline stays as the second payload) and the 43-pair sweep re-ran against it with
  `--network none` — 43/43, 40/43 count-match, the staged-tree result. pwiz-sharp side is up
  as a stack: **#4640** and **#4641** against #4619. Container changes verified but not yet
  pushed to PR #35.
- **pwiz-sharp PRs**: [#4640](https://github.com/ProteoWizard/pwiz/pull/4640)
  (`Skyline/work/20260904_vendor_resolution_fixes`) ->
  [#4641](https://github.com/ProteoWizard/pwiz/pull/4641)
  (`Skyline/work/20260904_vendor_bundled_installer`), both based on #4619's branch
- **Module**: `pwiz`
- **Container PR**: [#35](https://github.com/ProteoWizard/container/pull/35) on
  `Skyline/work/20260902_wine11_net10`
- **pwiz-sharp changes**: 13 files, UNCOMMITTED on `msconvert-parity` (branch is behind 8)
- **Module**: `msconvert` / CI infrastructure
- **PR**: (pending)
- **Related**: `4387ba67c2` "Ran the Windows-only vendor suites on Linux in identify-only mode" -
  identify-only proves the readers *recognise* the formats on Linux; this proves they can
  actually *read* them under Wine, with spectrum counts identical to native Windows.

## Why

The net10 port deleted the net472 leg. The existing Wine CI container cannot host it:

- `proteowizard/wine-dotnet` has exactly **one** tag, `winestaging10.6-net4.8-x64`. There is no
  .NET Core / .NET 10 variant, so this is not a matter of retargeting an existing image.
- Its Dockerfile pulls `SkylineTester.zip` from the **net472** master config, which the net10
  branch no longer produces.

The investigation below answers the two questions that had to be settled before any container
work was worth starting: does .NET 10 run under Wine at all, and do the Windows-only vendor
readers still read correctly there.

## Settled

### 1. .NET 10 runs under Wine, and no new base image is needed

`Stage-Tests.ps1` already bundles a private runtime into `bin/staging` (NETCore.App 10.0.11,
WindowsDesktop.App 10.0.11, fxr 10.0.11). Pointing `DOTNET_ROOT` at `Z:\pwiz\dotnet` is
sufficient - plain Wine plus the staged tree, with no dotnet-in-Wine install. The managed
`msconvert-sharp` executes and converts real vendor data this way.

### 2. .NET Framework is NOT what the vendor readers need - the VC++ redistributables are

> **CORRECTED 2026-09-04.** Half right. .NET Framework is indeed unnecessary. But the
> conclusion "install the VC++ redistributables into the prefix" was wrong, and the sweep
> below could not distinguish it from the real cause. Wine's builtin `msvcp140` /
> `vcruntime140` / `ucrtbase` are fine — which is why every vendor except Shimadzu passed on
> vanilla wine. **Wine has no MFC**, so `mfc140` was the single unresolvable module, and
> `winetricks vcrun2019` was incidentally supplying it. Shimadzu was the only reader affected
> because it was the one vendor whose app-local VC runtime staging was missing
> (`Shimadzu.csproj` now stages it, as `Agilent.csproj` does VC120 and `Bruker.csproj` VC90).
> The new base installs **no** VC++ redistributables and all 8 vendors work. Read the rest of
> this section as history.

This is the finding that matters. Sweep of 42 source+reference pairs across 7 vendors
(Agilent 11, Waters 13, Thermo 7, Bruker 6, Mobilion 2, Shimadzu 2, UIMF 1):

| image | wine | converted | count-match | Shimadzu `10nmol` | Shimadzu CJK name |
|---|---|---|---|---|---|
| `proteowizard/wine-dotnet:winestaging10.6-net4.8-x64` (current CI) | 10.6 Staging | 41/42 | 38/42 | 150 OK | **fails** |
| `scottyhardy/docker-wine:stable-10.0` | 10.0 vanilla | 42/42 | 38/42 | **0** | OK |
| `scottyhardy/docker-wine:stable-11.0` | 11.0 vanilla | 42/42 | 38/42 | **0** | OK |
| `winehq-staging` 11.16 | 11.16 Staging | 42/42 | 38/42 | **0** | OK |
| **11.0 + `vcrun2008 vcrun2019`, no .NET FW** | 11.0 vanilla | **42/42** | **39/42** | **150 OK** | OK |

The last row beats the current CI image on every axis.

Wine's builtin `msvcp*` / `msvcr*` reimplementations are not sufficient for the Shimadzu native
SDK. The genuine Microsoft redistributables currently arrive only as a side effect of
`winetricks dotnet48`; installing them directly gets the same result without `mscoree`. The
smoking gun was the proteowizard prefix's native DLL overrides - `msvcp140`, `vcruntime140`,
`ucrtbase`, `concrt140`, `atl140/90`, `msvcr90`, plus `"*mscoree"="native"`.

**The Shimadzu failure mode is silent**: exit 0, empty log, and a structurally valid mzML with
no `<spectrumList>` at all. Same class as the historic Agilent empty-spectra bug. On vanilla
Wine a user would get a plausible-looking empty result. Any container change must be validated
against spectrum counts, not exit codes.

### 3. Wine fidelity is exact

Three count mismatches are common to every image. Two were run natively on Windows:

| file | Windows | Wine | reference |
|---|---|---|---|
| Mobilion `ExampleTuneMix_binned5` | 19570 | 19570 | 101 |
| Waters `QC_LCMS2-2_23_268-1-1` | 2360 | 2360 | 10 |

Windows and Wine agree exactly. Those references were generated with different options
(Mobilion IMS combining, a Waters filter) and would mismatch on Windows too. So the honest
score for the recommended image is **39/39 on everything comparable** - full Wine/Windows
fidelity.

## Dead hypotheses - do not re-run these

Each died by measurement. Re-testing them is wasted time.

- *"Stock Wine is fine as-is"* - no. Vanilla silently returns zero spectra for Shimadzu.
- *"It's Staging vs vanilla"* - no. Staging 11.16 fails identically to vanilla 11.0.
- *"It's the Wine version"* - no. 10.0 and 11.0 are byte-identical in outcome, six upstream
  releases apart.
- *"Thermo is a good probe for native-code handling"* - no. Thermo CommonCore is pure managed;
  it proves nothing about Wine and native vendor DLLs. Use Agilent (mixed-mode `BaseTof.dll`
  imports MSVCR120), Sciex, or Shimadzu.

## Separately: a one-line fix for the currently-red CJK case in existing CI

The CJK-named Shimadzu file fails on `proteowizard/wine-dotnet` with mojibake:

```
Invalid name. : 'Z:\out\Shimadzu\20140312_e\x05-mix_column_1 (scheduled) d8'
```

Same failure as in the existing container CI log (`no files found matching
"20140312_e -mix_column_1 (scheduled) d8"`). Adding `LANG=C.UTF-8` / `LC_ALL=C.UTF-8` to that
image makes it convert cleanly - 494 KB, byte-identical in size to the stock image's output.

Scope note: this is specific to the `proteowizard/wine-dotnet` image. The stock images handle
that filename natively with or without the locale set, so it is not a general Wine fix.

## Artifacts to recreate (originals were in `ai/.tmp`, which is never committed)

> **SUPERSEDED 2026-09-04.** The real Dockerfiles now live in `ProteoWizard/container` PR #35
> (`wine/Dockerfile` + the root `Dockerfile`). Two differences from the candidate below, both
> load-bearing: it is `ubuntu:24.04`, not 20.04 (WineHQ's focal builds **stop at 10.6** — the
> old pin was the ceiling, not a preference; wine 11 needs jammy or noble), and it installs
> **no winetricks VC++ runtimes at all**. It also needs `WINEDLLOVERRIDES="mscoree,mshtml="`
> scoped to the `wineboot` RUN — without it wineboot hangs forever on the Mono/Gecko download
> prompt, and leaving it set at run time breaks the payload with a bogus
> `System.Runtime.dll ... Module not found`. Kept below as the historical starting point.

### Candidate Dockerfile (historical)

```dockerfile
# Candidate base for a net10 Wine container: stock WineHQ stable, the genuine Microsoft
# VC++ redistributables, and NO .NET Framework. The net10 tree carries its own runtime,
# so mscoree is not needed - but the vendor SDKs are native code and do need the real
# redistributables rather than Wine's builtin reimplementations.
FROM scottyhardy/docker-wine:stable-11.0

ENV WINEDEBUG=-all
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV WINEPREFIX=/wineprefix64
ENV WINEARCH=win64

RUN mkdir -p /wineprefix64 \
 && xvfb-run -a wineboot -u \
 && xvfb-run -a winetricks -q vcrun2008 vcrun2019 \
 && wineserver -w \
 && rm -rf /tmp/.X* /root/.cache/winetricks || true
```

### Sweep harness

`/manifest.txt` is one pipe-delimited line per test file,
`vendor|subdir|source|stem`, e.g.

```
Agilent|Reader_Agilent_Test.data|MRM Neg C5.d|MRM Neg C5
Shimadzu|Reader_Shimadzu_Test.data|10nmol_Negative_MS_ID_ON_055.lcd|10nmol_Negative_MS_ID_ON_055
ABI|Reader_ABI_Test.data|swath.api.wiff2|swath.api
```

```sh
#!/bin/sh
cd /pwiz || exit 1
ok=0; fail=0
while IFS='|' read -r vendor sub src stem; do
  [ -z "$vendor" ] && continue
  outdir="/out/$vendor/$stem"
  rm -rf "$outdir"; mkdir -p "$outdir"
  if wine msconvert.exe "Z:/vr/$vendor/$sub/$src" -o "Z:/out/$vendor/$stem" > "$outdir/_convert.log" 2>&1 \
     && [ -n "$(ls "$outdir"/*.mzML 2>/dev/null)" ]; then
    ok=$((ok+1)); echo "ok   $vendor/$src"
  else
    fail=$((fail+1)); echo "FAIL $vendor/$src"
  fi
done < /manifest.txt
echo "SWEEP done: converted=$ok failed=$fail"
```

**Harness traps that already cost a cycle once:**

- Pass the script as a **file**, not an inline `-c` string. Shell quoting through
  `docker run` doubled the backslashes, every path was mangled, and the sweep reported "OK"
  for all four vendors while producing **zero output files** - the exit code was still 0.
  Use forward-slash `Z:` paths and count output files explicitly.
- Do not verify Linux case-sensitivity over a Docker Desktop bind mount. Those inherit NTFS
  case-insensitivity, so a case bug cannot reproduce there. Test on the container's own
  filesystem.

## Remaining work

- [x] Build the wine 11 base in `ProteoWizard/container` — `wine/Dockerfile`, PR #35.
      Named `proteowizard/wine:stable11.0-x64`, NOT `wine-vcrun`: no VC++ redistributables
      are installed at all (see the correction in §2 above).
- [x] Repoint the app image at the new base — PR #35.
- [x] Artifact wiring — a NON-ISSUE, the TODO was stale. `tcbuild.bat` sets
      `DISTRO_ZIPS=SkylineTester.zip SkylineNightly.zip BiblioSpec.zip`, so the net10 branch
      does produce it. Superseded anyway: the payload is now the installer (below).
- [x] Sweep against the built image — 43/43 converted, 40/43 count-match (the 43rd pair is
      the `Neg_MS_002_1scan.d` fixture added since the original sweep).
- [x] `LANG`/`LC_ALL=C.UTF-8` — in the new base; the CJK Shimadzu fixture matches.
- [x] Vendor-bundled installer: `build.ps1 -WithVendorSdks` produces
      `ProteoWizard-WithVendorSdks-Setup-<ver>.exe` (103.8 MB). Bundled .NET runtime PLUS
      every Windows vendor SDK pre-extracted into VendorSdkLoader's cache. **7/7 vendors
      convert with `--network none`.**
- [x] `tcbuild.bat` builds it (via a new `build.bat --with-vendor-sdks` flag; opt-in so a
      developer build does not pay ~30 s / ~26 MB).
- [x] Installer renamed `ProteoWizard-Sharp` -> `ProteoWizard` (26 replacements).
- [x] **PR #35: add `wineserver -k` after the install step.** The root-cause fix for the
      Shimadzu hang (see §"The Shimadzu hang" below). It lives in the app Dockerfile's new
      install stage — the item was only actionable once there WAS an install step there.
- [x] **PR #35: switch the payload from the staged tree to the vendor-bundled installer**,
      and re-run the 43-pair sweep against an image built that way. **43/43 converted,
      40/43 count-match with `--network none`** — identical to the staged-tree baseline.
      Plus ABI 4/4 and all three entry points. See the 2026-09-04b log entry.
- [x] **Two payloads, not one** — the installer replaces only the pwiz half; `SkylineTester.zip`
      stays as the Skyline half. See §"The image has TWO payloads".
- [x] Commit the 13 pwiz-sharp files — done as a two-PR stack against #4619:
      **#4640** (vendor-resolution fixes) and **#4641** (vendor-bundled installer variant,
      based on #4640). Full build + test suite green before committing.
- [ ] Push the container changes to PR #35 (Dockerfile two-payload rewrite, `.gitattributes`,
      `.gitignore`) and update its description. Verified locally, not yet pushed.
- [ ] Consider extending `Installer.Tests` beyond the per-user variant, and to the
      `-WithVendorSdks` artifact specifically — nothing currently gates that variant.

## The image has TWO payloads — ANSWERED

**`master` has always had two:** `pwiz-bin-windows-*.tar.bz2` into `C:\pwiz` and
`SkylineTester.zip` into `C:\pwiz\skyline`, with `WINEPATH="C:\pwiz;C:\pwiz\skyline"`. PR #35
collapsed them into one on the reasoning that Skyline's staging tree already carries
msconvert. **That was the wrong simplification** — it silently made
`proteowizard/pwiz-skyline-i-agree-to-the-vendor-licenses` a Skyline-less image, and it is
why "switch the payload to the installer" first read as dropping Skyline.

The installer replaces the **pwiz** payload only. It stages 130 files — msconvert,
MSConvertGUI, SeeMS, idconvert — and no `Skyline.exe`, `SkylineCmd.exe` or `BlibBuild.exe`,
so it was never a candidate to replace the Skyline half.

Two consequences worth keeping:

- **`C:\pwiz` must stay first in `WINEPATH`.** A real net10 `SkylineTester.zip` ships its own
  msconvert next to Skyline, so both directories contain one. Verified by staging a decoy
  `msconvert.exe` (a copy of `7za.exe`, which names itself in its banner) at
  `C:\pwiz\skyline\msconvert.exe`: `C:\pwiz` still answers.
  Probe: `ai/.tmp/wine-probe/winepath-order.sh`.
- **One runtime serves both.** `DOTNET_ROOT` points at `C:\Program Files\dotnet`, the
  machine-wide runtime the installer lays down, so the Skyline payload's own bundled
  `C:\pwiz\skyline\dotnet` goes unused.

Still unverified locally: the Skyline half. The only `SkylineTester.zip` on this machine is a
**2019 net472 artifact** — no `Skyline.exe`, no `dotnet` folder. PR #35 already carries this
caveat ("needs one build against a real net10 CI artifact"); it is unchanged, not made worse.

## Open question — ANSWERED

`vcrun2008` / `vcrun2019` are **both unnecessary**. Neither is installed in the new base and
all 8 vendors work. The VC++ runtimes the vendor SDKs need are deployed app-local by
pwiz-sharp; `mfc140` was the only one wine has no builtin for, and the only one actually
missing. See §2.

## The Shimadzu hang (the expensive one — read before touching this)

**Root cause: the Inno installer leaves a wine process alive in the prefix. Starting a
conversion before it exits deadlocks the Shimadzu reader.** Fix: `wineserver -k` after the
install. NOT `-w` — that waits on the very process that is stuck and blocks forever (a probe
container sat on it for an hour). Same `-w` vs `-k` trap already hit building the base image.

Evidence, one run, same container:

| settle step after install | result |
|---|---|
| `wineserver -k` | rc=0, 3 s, 150 spectra |
| `sleep 20` | rc=0, 2 s, 150 spectra |
| none | rc=124, 90 s timeout, no output |

Base rate without the settle step: **12/12 hangs** across four fresh containers. The two
accidental successes during the investigation both happened to do unrelated filesystem work
(a `mkdir`, a 325-file `cp`) between install and conversion, which bought ~20 s.

**Hypotheses refuted along the way — do not re-run these.** Each was tested, not reasoned
about. The hang looked payload-shaped and is not:

- Payload contents (53/53 Shimadzu DLLs byte-identical between cache and build output)
- `msconvert.deps.json` (byte-identical between the GUI and CLI builds)
- App-local vs cache placement of the vendor DLLs
- Cache path location (relocated out of `%PROGRAMDATA%` into the install dir)
- .NET runtime version AND provenance (wine-installed vs copied from a real Windows host)
- Whether the runtime is installed into the prefix at all
- Working directory (`/wineprefix64`, `/data`, `/tmp`)
- Builtin vs native VC140 CRT (`WINEDLLOVERRIDES=...=n`)
- The missing `C:\users\root\Temp` directory — I wrongly credited this as the fix at one
  point; creating it hangs 4/4. The base image creates it anyway, on its own merits.
- Invocation form (`wine64_anyuser`, absolute path, bare name — all three work in the good image)
- The container image itself (the installed copy hangs even inside the image where the
  staged tree converts in 3 s)

**Separately real, and still needed:** the VC140 runtime must be staged into the Shimadzu
cache directory. Its natives are loaded from there by full path, so the loader resolves their
imports from that directory rather than the exe's. Without it Shimadzu returns `rc=0` with an
**empty** mzML — a silent wrong answer, not a failure. `build.ps1` does this; removing it
reproduces `spectra=0`.

## Four vendor-resolution bugs found and fixed (all pre-existing)

Reproduced on **native Windows with the stock installer and the network up** — nothing to do
with wine or the container. They survived because the resolver prefers app-local DLLs, which
every dev and CI build has; only an installer-based install takes the cache path, and
`Installer.Tests` only covered Thermo/Waters/Bruker.

1. **Agilent, two bugs.** `BaseCommon`/`BaseDataAccess`/`BaseError`/`BaseTof` were listed
   under Bruker's prefixes but are Agilent MHDAC files (Bruker's archive ships exactly two
   DLLs: `baf2sql_c`, `timsdata`). `FindPin` is first-match-wins and Bruker precedes Agilent.
   Then, once past that: the prefix `MIDAC.` can never match the assembly `MIDAC` —
   `StartsWith` with a trailing dot the name lacks.
2. **Sciex.** `Wiff2LoadContext` loads the SDK with `LoadFromAssemblyPath`, which consults no
   resolver. Added a cache fallback via `EnsureExtracted("ABI")`, mirroring Bruker's
   `CompassXtractActivationContext`.
3. **Mobilion.** `MobilionShim` was listed as a vendor prefix, so the staging filter stripped
   pwiz-sharp's *own* shim, which no archive could supply. Removing it exposed the real bug:
   the shim links `MBI_SDK.lib`, so MBI_SDK is a **static import the OS loader resolves** — a
   path no `DllImportResolver` sees. A static ctor now preloads it from the cache by full path.
4. **Installer packaging.** The installer staged MSConvertGUI + SeeMS but ships
   `msconvert.exe`, whose own project resolves five transitive assemblies the GUI's does not —
   including `System.Configuration.ConfigurationManager`, which Agilent's MHDAC needs to read
   `BaseDataAccess.dll.config`. Also needed msconvert's `wiff2/` subdirectory (patched
   `Unity.Abstractions` + SQLite 1.0.109) which only the CLI bin has. Staged top-level-only:
   recursing pulls in a duplicate `win-x64/` RID tree (+45 MB).

`Installer.Tests` now converts one fixture per vendor (9 fixtures / 8 vendors, was 4/3) and
**accumulates** failures instead of throwing on the first — Agilent alone was masking Sciex
and Mobilion entirely.

## Harness traps (cost real time this session)

- **Do not copy a tree containing both `foo` and `foo.exe` with MSYS `cp`.** Git Bash maps
  `foo` <-> `foo.exe`, so `cp -r` silently overwrote the PE `msconvert.exe` with the Linux ELF
  apphost of the same stem. Use `robocopy` or PowerShell. This cost a whole misdiagnosed
  Bruker "failure".
- **Invoke the apphost (`msconvert.exe`), not `dotnet msconvert.dll`.** Bruker's BDal factory
  resolves its plugins relative to the *host executable's* directory; via `dotnet.exe` that is
  the dotnet folder and Bruker fails with `TypeNotInFactory`.
- **Backslashes get mangled** writing shell heredocs and `printf` through the tooling — a
  cache-root marker came out as `C:\pwendor-cache` and invalidated a whole test. Write such
  files from the host, or verify the bytes.
- **Docker Desktop shares paths by string prefix** (`FilesharingDirectories`). An unshared
  path makes `docker run` hang with *no container ever appearing* in `docker ps` — it looks
  exactly like a hung container. `C:\dev\pwiz` was shared, which is why `C:\dev\pwiz-winetest`
  worked and `C:\dev\winetest` did not.
- **`Select-Object -Last N` / `Out-String` buffer the whole stream**, so a hung `docker run`
  shows an empty log. `Tee-Object` to a file to see progress.
- **PowerShell is case-insensitive**: a `$Dest` parameter and a `$dest` local are the same
  variable. Self-corrupting staging paths until renamed.

## Performance (measured, n=3, single session)

msconvert-sharp, `--combineIonMobilitySpectra`, identical spectra counts + output bytes
verified across every leg. Full detail in `ai/.tmp/wine-perf/results.txt`.

| vendor | Windows | Wine 10.6-staging | Wine 11.0 | Linux native |
|---|--:|--:|--:|--:|
| Thermo | 279.2 | **239.1** | 255.1 | **192.7** |
| Waters | 141.7 | 136.7 | **133.7** | 167.0 |

- **Wine costs nothing** — both versions beat native Windows here (-4% to -14%).
- **The two wine versions are equivalent** (10.6-staging -6% Thermo, +2% Waters), so the
  image choice rests on correctness/simplicity, not speed.
- **Native Linux is not uniformly better**: Thermo -31%, but Waters +18% vs Windows
  (`libMassLynxRaw.so` is slower than the Windows DLL).
- Windows is the noisiest environment (16.7% spread vs 1.8-3.3% for wine).
- **Two traps**: the first Windows replicate of a freshly staged series is a cache-warm
  outlier, and the same config drifted ~10% between sessions. Never compare across sessions;
  re-run every leg you intend to compare.

## Progress Log

### 2026-09-02 — wine 11 base + app image (PR #35)

Built `wine/Dockerfile` (ubuntu:24.04 + winehq-stable 11.0, no .NET Framework, no VC++
runtimes, corefonts, UTF-8 locale) and repointed the root Dockerfile at it. 4.52 GB vs
5.74 GB for `wine-dotnet`. Verified with the 43-pair sweep **inside the built image**:
43/43 converted, 40/43 count-match, the 3 diffs being the known reference-generation
artifacts. Opened PR #35.

### 2026-09-03 — performance, then the installer

Three-way perf comparison (Windows / wine / native Linux) at n=3, plus a wine-version
column. Conclusion: wine costs nothing, the two wine versions are equivalent, native Linux
is not uniformly better. Numbers in the section above.

Then: `build.ps1 -WithVendorSdks`, a third installer variant carrying the .NET runtime AND
the vendor SDKs, pre-extracted into VendorSdkLoader's cache layout with the `.ok` markers so
the loader neither downloads nor extracts. Installing it revealed four pre-existing
vendor-resolution bugs, all reproduced on native Windows with the stock installer — see the
section above. Extended `Installer.Tests` from 4 fixtures / 3 vendors to 9 / 8, which is what
found them, and made it accumulate failures rather than abort on the first.

### 2026-09-04 — Shimadzu root cause, rename, tcbuild

Shimadzu hung under wine from an installer-based install. Eleven hypotheses tested and
refuted (listed above) before finding it: **the installer leaves a wine process alive, and
converting before it exits deadlocks the reader**. `wineserver -k` after the install fixes
it; `-w` blocks forever on that same process. Offline sweep now **7/7 with `--network none`**.

Two corrections worth recording because both were wrong for a while: the "missing Windows
TEMP directory" was NOT the fix (hangs 4/4 with it present), and the app-local vendor payload
I added on that wrong hypothesis was unnecessary — cache-only is also 7/7 and 17.7 MB
smaller, so it was removed. Staging VC140 into the Shimadzu cache dir IS still required.

Also: renamed `ProteoWizard-Sharp` -> `ProteoWizard` across the installer (26 replacements,
product name + all three output filenames + the Linux tarballs + the test's discovery glob),
and wired `--with-vendor-sdks` through `build.bat` so `tcbuild.bat` builds the vendor variant
on CI while a developer build does not pay for it. Verified all three arg paths.

### 2026-09-04b — the app image now installs the installer; sweep re-run against it

The app Dockerfile's payload is the vendor-bundled installer instead of `SkylineTester.zip`.
A first stage (`FROM proteowizard/wine:stable11.0-x64 AS install`) runs setup under `xvfb-run`
with `/VERYSILENT /CURRENTUSER "/DIR=C:\pwiz"`, then `wineserver -k`, and the final stage copies
forward only what the install produced: `C:\pwiz`, `C:\Program Files\dotnet` and
`C:\ProgramData\ProteoWizard`. The stage boundary is what keeps the 104 MB setup EXE out of the
shipped image — an `rm` in a later layer would not reclaim it. **4.94 GB, vs 5.04 GB for the
staged-tree image.**

**43/43 converted, 40/43 count-match, with `--network none`** — byte-for-byte the same verdict
as the staged-tree baseline, including the CJK Shimadzu fixture and the 150-spectrum
`10nmol` case. No hang: the install is a build-time layer, so the wineserver race cannot
occur at run time.

Then two things the earlier evidence did not cover:

- **ABI/Sciex.** It is absent from the 43-pair manifest because one `.wiff` holds several
  samples, so inputs do not pair with references by stem. Pairing the other way round —
  convert, then match each PRODUCED mzML to a reference of the same name — gives
  **4/4 converted, 11 count-matches, 1 indexRange diff, 1 with no reference (616 spectra)**.
  Script: `ai/.tmp/wine-probe/abicheck.sh`.
- **Entry points.** `root`/`wine64_anyuser`, uid 1450 (galaxy)/`wine64_anyuser`, and `mywine`
  all convert to 85 spectra. Worth checking because the payload moved out of `C:\pwiz\skyline`
  and `mywine` builds a private prefix from symlinks into `/wineprefix64`.

**All four count differences are now explained mechanically, not just labelled "known".** The
reference mzMLs are deliberately truncated by `ReaderTestConfig::indexRange`, and every
reference count is exactly the span + 1: ABI `7600ZenoTOFMSMS` `(0,20)`→21 vs 2650, both
Mobilion `(0,100)`→101 vs 11773/19570, Waters `QC_LCMS2` `(0,9)`→10 vs 2360. A plain
`msconvert` run emits the whole file, so these can never match and are not regressions.

**Found and fixed a pre-existing defect: `mywine` is broken in every image built from a
Windows checkout.** Windows clones default to `core.autocrlf=true`, so `mywine` is checked out
with CRLF, its shebang becomes `/bin/sh\r`, and the kernel reports the missing interpreter as
`mywine: not found` — pointing at the script rather than at its first line. The committed blob
is LF, so this never reproduced on a Linux build and is invisible in `git diff`. Fixed with a
`.gitattributes` (`* text=auto eol=lf`); `mywine` passes after it. Same class as the
LF-`.bat`-file trap in MEMORY.md, in the other direction.

**Correction within the same session: the image has two payloads, not one.** `master` puts
ProteoWizard in `C:\pwiz` and Skyline in `C:\pwiz\skyline`; PR #35 had collapsed them. The
installer replaces only the pwiz half. Rebuilt that way, the sweep is **byte-identical** to
the installer-only run (43/43, 40/43, same three diffs), and `C:\pwiz` still wins on
`WINEPATH` against a decoy `msconvert.exe` planted in the skyline directory. Details in
§"The image has TWO payloads".

**The 13 pwiz-sharp files are committed and up as a stack against #4619**: **#4640**
(vendor-resolution fixes, 7 files) and **#4641** (vendor-bundled installer variant, 6 files,
based on #4640). Split two ways rather than the four the handoff suggested because `build.ps1`,
`Setup.iss` and `InstallerTests.cs` each carry the variant AND the rename in interleaved hunks.
Gate before committing: `build.bat Release --i-agree-to-the-vendor-licenses --with-vendor-sdks`
after fast-forwarding the 8 upstream commits — build succeeded, all three installers produced,
every suite green (Agilent 17, Waters 21, Bruker 15+1, Thermo 15, Sciex 8, Mobilion 2,
Shimadzu 2, UIMF 2, UNIFI 44, BiblioSpec 142, Analysis 177, MsData 85 …), only the known
elevation-gated `Install_PerMachine` skip.

The container changes are verified but NOT pushed to PR #35.

**Next session handoff**: For detailed startup protocol, read
`ai/.tmp/handoff-20260901_net10_wine_container.md` before starting work.
