# Build a net10 Wine container for the Windows-only vendor readers

## Branch Information
- **Checkout**: investigation ran from `C:\dev\pwiz-net8`; container work belongs in `ProteoWizard/container`
- **Branch**: not created yet
- **Base**: `master` for the container repo; the staged tree comes from `Skyline/work/20260612_net8_port`
- **Created**: 2026-09-01
- **Status**: investigation complete, container not built
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

### Candidate Dockerfile

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

- [ ] Build the image above in `ProteoWizard/container` and push a tag (suggest
      `proteowizard/wine-vcrun:stable11.0-x64`, i.e. dropping `-net4.8` from the name since
      the framework layer is gone).
- [ ] Dockerfile for the net10 conversion job: take the staged net10 tree, set
      `DOTNET_ROOT=Z:\pwiz\dotnet`, set the UTF-8 locale, drop the `net4.8` base.
- [ ] Artifact wiring - the current config pulls `SkylineTester.zip` from the net472 master
      config, which the net10 branch does not produce. Needs a net10 artifact source.
- [ ] Re-run the 42-pair sweep against the built image and confirm 42/42 converted, 39/42
      count-match, Shimadzu `10nmol` at 150 spectra.
- [ ] Independently of the above, add `LANG=C.UTF-8` / `LC_ALL=C.UTF-8` to the existing
      `proteowizard/wine-dotnet` image to clear the CJK Shimadzu failure in current CI.

## Open question

Only `vcrun2008 vcrun2019` were tested, chosen from the override list in the working prefix.
Whether both are load-bearing, or which vendor needs which, was not narrowed down. Worth one
run each if image size matters; otherwise install both.
