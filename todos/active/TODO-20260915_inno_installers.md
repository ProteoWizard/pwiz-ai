# TODO-20260915_inno_installers.md

## Branch Information
- **Branch**: `Skyline/work/20260915_inno_installers`
- **Base**: `Skyline/work/20260612_net8_port` (the .NET port branch, PR #4619)
- **Created**: 2026-09-15
- **Status**: In Progress
- **Module**: `skyline`
- **PR**: [#4676](https://github.com/ProteoWizard/pwiz/pull/4676)

## Objective

Inno Setup installers for Osprey and Skyline, analogous to the existing pwiz-sharp
installer (`pwiz-sharp/installer/Setup.iss`), plus a "version-specific install" option
for pwiz and Osprey. Decided 2026-09-15; supersedes the Velopack recommendation in
`TODO-20260701_clickonce_replacement.md` (Inno for all three products).

### Requirements (from Matt, 2026-09-15)

- All three installers first ask "install for me" vs "for all users" (admin). Inno's
  `PrivilegesRequired=lowest` + `PrivilegesRequiredOverridesAllowed=dialog`.
- **Osprey**: same as pwiz minus the Explorer context-menu tasks.
- **Skyline**: functionally equivalent to the ClickOnce installer AND takes over the WiX
  admin installer's job.
  - Per-user install: fixed location `%LocalAppData%\Programs\Skyline[-daily]` (Inno's
    `{autopf}`; changed from `Apps` on 2026-09-15 review - Programs is the standard
    per-user location, Apps\2.0 was ClickOnce's private store), license and directory
    pages skipped.
  - Admin install: license and directory page shown, default `%ProgramFiles%\Skyline[-daily]`.
  - Two channels, `Skyline` and `Skyline-daily`: distinct AppIds, install side by side;
    a newer version of a channel replaces the previous one in place.
- **pwiz and Osprey**: option for a version-specific install that is never replaced by a
  newer version and keeps its own versioned Start Menu shortcuts. Default is the
  standard (replace-in-place) install.

## Layout

```
pwiz-sharp/installer/
  Setup.iss                          pwiz (ProteoWizard-Sharp); now standard-by-default
  common/DotNetDesktopRuntime.iss    bundled / NoNetRuntime .NET desktop runtime (pwiz + Skyline)
  common/InstallType.iss             standard-vs-versioned wizard page + AppId/dir/group code
  build.ps1, Ensure-InnoSetup.ps1    unchanged shape
pwiz_tools/Osprey/Installer/
  Setup.iss                          replaces Osprey.wxs; package.ps1 -Setup builds it
pwiz_tools/Skyline/Executables/Installer/
  Setup.iss, build.ps1               new; WiX template left for the net472 Jam leg
```

## Tasks

- [x] Shared includes (runtime detection, install-type page) with event attributes so
      each product script keeps its own event handlers
- [x] pwiz Setup.iss: standard install default, versioned as option; NOTES.md; Installer.Tests
- [x] Osprey Setup.iss + package.ps1 (-Setup replaces -Msi), tcbuild/tcpackage.bat, README,
      Osprey.wxs removed
- [x] Skyline Setup.iss + build.ps1 (stage Skyline x64 Release output, runtime, 2x ISCC) +
      Test-Installer.ps1 + README.txt
- [x] Skyline: file associations (.sky/.skyd/.skyp, per-channel ProgIds, shared extension
      values released on uninstall only if still ours), Start Menu group "MacCoss Lab, UW",
      HKA\Software\MacCossLabUW\<channel>\InstallDir for discovery
- [x] Compile all three with ISCC; silent install/uninstall smoke of each (see Progress)
- [x] /code-review max round (2026-09-15 afternoon): 15 findings, 13 fixed, 2 judged
      (see Progress); re-verified by compile + build.ps1 + pwiz Installer.Tests
- [x] Committed (0e6d1ac5a8) and PR #4676 opened for discussion, 2026-09-16

### 2026-09-17

- First CI round on #4676: Core Windows/Linux .NET and Skyline Windows .NET green. Osprey
  Windows .NET built and PUBLISHED Osprey-Setup-26.1.1.259.exe through the Ensure-InnoSetup
  bootstrap (no WiX on the agent) but was marked failed by TeamCity's freeze.settings.error:
  the base moved the Osprey configs into versioned .teamcity settings after the branch
  point. Skyline Perf/Tutorial: TestAlphaPeptDeepBuildLibrary failed opening its own input
  blib (SQLite CantOpen) - environmental, passed on the identical base commit, no nightly
  history. Merged the base twice (second merge brought #4640's ProteoWizard rename +
  WithVendorSdks variant into Setup.iss/Installer.Tests; resolved keeping both).
- Osprey Linux .NET (new config #4682, failing on the base with "A compatible .NET SDK was
  not found"): tcbuild.sh now sources pwiz-sharp/scripts/ensure-dotnet.sh like Core Linux
  does (36389a1418). Bootstrap verified under WSL from the Osprey directory. The base keeps
  failing until this lands or that one commit is cherry-picked onto it.

### 2026-09-21

- Nick's review: a ProgId allows no punctuation but periods, so `Skyline-daily.Document.1`
  was not a legal name. The daily channel's ProgIds are now `SkylineDaily.Document.1` /
  `.Data.1` / `.Pointer.1` (9acec4d512; Setup.iss ProgIdPrefix and Test-Installer.ps1);
  install/uninstall cycle with the hand-back re-verified. Thread replied to and resolved.
- Merged the base again on 2026-09-18 (31776743f2); the base had landed its own Osprey Linux
  SDK bootstrap (c927f5e019), so tcbuild.sh was resolved to the base's version and the
  branch is back to the 18 installer files.

## Follow-ups (not in this PR)

- UpgradeManager: replace NullDeployment with a check against skyline.ms for a newer
  Setup.exe, download it and run it silently (/CURRENTUSER or /ALLUSERS from the
  install's own hive, /VERYSILENT /NORESTART), then restart. That is the ClickOnce
  auto-update UX the installer itself cannot provide.
- Discovery: SkylineRunner (ListPossibleSkylineShortcutPaths), SharedBatch's
  SkylineInstallations and the MCP server's SkylineInstallation still look for the
  ClickOnce .appref-ms; teach them HKCU|HKLM\Software\MacCossLabUW\<channel>\InstallDir
  (and the fixed %LocalAppData%\Programs\<channel> path). SkylineRunner is hard-coded to the
  daily channel (AssemblyName SkylineDailyRunner); the release channel needs the other name.
- SkylineBatch: the WiX admin .msi bundled SkylineBatch.exe + a shortcut; the .NET SkylineBatch
  builds to its own bin, so bundling needs a staging merge (identical shared DLLs) and a
  second shortcut.
- ClickOnce migration: detect an existing ClickOnce Skyline[-daily] and its user.config
  (see closed PR #4620's UserConfigMigrator) on first launch of an Inno-installed Skyline.
- Signing: build.ps1 -SignToolCommand / package.ps1 -Sign hand Inno a sign tool; the
  DigiCert KSP command from the Jamfile has not been run against the real certificate.
- CI: Skyline's tcbuild.bat does not build the installer yet (pwiz-sharp's does via
  build.bat; Osprey's tcbuild.bat now does). Add an installer step + Test-Installer.ps1
  once the branch's CI shape for it is decided.
- pwiz-sharp: installer directory is still %LocalAppData%\Programs\ProteoWizard-Sharp
  (Inno's {autopf}); the cpp installer used %LocalAppData%\Apps\ProteoWizard <ver>.

## Progress

### 2026-09-15

- Branch created from origin/Skyline/work/20260612_net8_port (ea391bde4e). The branch is
  checked out in the pwiz-net8 worktree, so this work branch is the way to work on it in
  C:\dev\pwiz.
- C:\dev\pwiz has stray untracked sources that SDK-style csprojs glob in
  (pwiz_tools/Shared/CommonUtil/SystemUtil/Range.cs, CommonUtil/Directory.Build.props,
  CommonUtil/GUI/, BiblioSpec/Library.cs, ProteowizardWrapper/*.cs strays, Skyline/*2.ja.resx
  ...). `dotnet publish` of Osprey fails here on Range.cs (a net472 polyfill of System.Index
  that conflicts with the BCL on net10). Payloads for the smoke tests were therefore built
  from the clean pwiz-net8 worktree (Osprey: its own package.ps1 publish; Skyline: its
  bin\x64\Release\net10.0-windows, 26.1.1.245).
- Inno facts that shaped the design: AppId may be a {code:} constant (real value needed
  only just before install), which requires UsePreviousLanguage=no and
  UsePreviousPrivileges=no; event attributes (`<event('X')>` on the line BEFORE the
  declaration) let includes and the product script each own handlers; a `;` comment is
  Pascal-parsed once a [Code] section is open, so Code-only includes start with [Code] and
  a (* *) comment; ISPP `#define`s that must survive Inno's own parameter parser need the
  inner quotes doubled (the Skyline OpenCommand).
- pwiz: compiled both variants; version-specific silent install/uninstall verified;
  Installer.Tests rebuilt (record struct InstallKey; versioned leg with the msconvert smoke,
  standard leg Inconclusive when a real standard install exists). Result here: versioned leg
  passed (4 vendor conversions), standard leg Inconclusive because a stale 0.1.0 install from
  May sits under the standard AppId at %LocalAppData%\Programs\ProteoWizard-Sharp.
- Osprey: Osprey-Setup-26.1.1.253.exe (30 MB from a 91 MB self-contained publish, 18 s);
  standard per-user install adds the dir to HKCU PATH, writes InstallPath, two Start Menu
  shortcuts, osprey --version runs; uninstall restores PATH and removes everything.
  Version-specific flavor verified too (no InstallPath, versioned dir/group, PATH entry
  removed on uninstall).
- Skyline: Skyline-daily-Setup-26.1.1.245.exe 165 MB (bundled runtime) /
  NoNetRuntime 52 MB, ~1 min per ISCC pass with lzma2/ultra64.
- Review round (/code-review max), fixed: Osprey New-OspreyZip had been deleted with the
  WiX code (every package.ps1 run without -NoZip died); Skyline staging stripped
  unimod.xml/modifications.xml (BlibBuild data) - now only doc XML beside a same-named
  dll/exe is dropped, and the stage is asserted to hold both; a stray 209 MB
  self-contained msconvert `win-x64\` publish folder in the net8 worktree's Skyline bin was
  riding into the installer (Skyline.csproj's msconvert Content glob now excludes RID
  folders, build.ps1 skips them and refuses a stage holding coreclr.dll; installers went
  158/101 MB -> 108/51 MB); trailing separator on -SkylineBinDir; -SignToolCommand quotes
  -> $q; Osprey sign command double-quoted $f and did not $$-escape; relative -OutputDir;
  ProgIds moved to <channel>.Document.1 etc. because every ClickOnce install registered
  Skyline.Document.0 for both channels, plus the extension's previous owner is recorded at
  install and handed back on uninstall, and our ProgId is deleted only while its command
  points into {app}; association/PATH edits moved to usUninstall (before the uninstaller's
  broadcast); NoNetRuntime abort now SuppressibleMsgBox + no browser when silent; runtime
  root resolved per architecture (ARM64 -> dotnetd) and DOTNET_ROOT[_X64]; legacy WiX
  .msi detected via MsiEnumRelatedProducts (new common/LegacyMsi.iss) and a per-machine
  install over it refused; Skyline warns interactively when the channel is installed in
  the other mode; Osprey shortcut WorkingDir literal %USERPROFILE% and set ""PATH"" quoting;
  version-specific re-install finds its earlier directory from its own uninstall key;
  /GROUP guard dropped (Inno ignores /GROUP with DisableProgramGroupPage=yes); pwiz test
  checks both hives before each leg (Inno suffixes DisplayName with "(All users)" when the
  other hive has the AppId).
- Review round, judged and left: UsePreviousPrivileges=no stays on Skyline (Matt asked
  for the mode prompt every run; Inno's =yes skips it on upgrades) - documented that silent
  upgrades must pass /ALLUSERS or /CURRENTUSER; the InstallType "decide in InitializeSetup"
  redesign (a pre-wizard dialog instead of a page) not taken, the include documents the
  limit and recovers the versioned directory itself; pwiz.vcxproj toolset edits are Matt's
  local changes and are not staged.
- Verified after the round: all three scripts compile; build.ps1 rebuilt Skyline-daily with
  the leaner stage; pwiz Installer.Tests versioned leg passed. Matt's interactive installs
  of all three products (pwiz standard upgraded the stale 0.1.0 in place) are on the
  machine, so the Skyline/Osprey uninstall-cycle re-tests wait for his go-ahead.
