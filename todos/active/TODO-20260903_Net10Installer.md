# TODO-20260903_Net10Installer.md

## Branch Information
- **Checkout**: `I:\git_i\sky_netinstaller`
- **Branch**: `Skyline/work/20260903_Net10Installer`
- **Base**: `Skyline/work/20260612_net8_port` (the .NET 10 port, PR #4619)
- **Created**: 2026-09-03
- **Status**: In Progress
- **GitHub Issue**: (none yet)
- **Module**: `skyline`
- **PR**: (pending)

## Objective

Ship the .NET 10 Skyline through **one Inno Setup installer** that replaces both the
ClickOnce deployment ordinary users install today and the separate administrator `.msi`
(`Executables/Installer`, WiX). Along the way fix the problems the admin install has always
had: a per-machine exe folder that users cannot write to, external tools landing in that
folder, and every user (and SkylineCmd) keeping a separate `user.config` that an
administrator cannot seed.

This picks up the three items the ClickOnce attempt deferred
(`TODO-20260825_net8_clickonce.md`, PR #4620, "Deferred to a separate work item"): where
`user.config` lives, SkylineCmd sharing Skyline's settings, and admin-installed tools
reaching ordinary users. PR #4620 stays as the record of the ClickOnce publish and signing
findings (dotnet-mage, KeyLocker, deploymentProvider); none of that is reused here.

## What exists on the branch

| SHA | What |
|---|---|
| `45ada09f3` | `Util/ClickOnceInstallations.cs` + `Program.MigrateSettingsFromClickOnceInstallation`: on first run (no `user.config` yet) find the ClickOnce installations in `%LOCALAPPDATA%\Apps\2.0`, pick the one Programs and Features still lists (else highest version), and copy its `user.config` forward. `ClickOnceInstallationsTest` covers the search. |
| `f7af5e680` | `Util/UserConfigSettingsProvider.cs`: a `SettingsProvider` (wired on `Settings` via `[SettingsProvider]`) that keeps `user.config` beside the Skyline assembly in the `LocalFileSettingsProvider` file format, so a copied ClickOnce file reads as is. Unknown settings are preserved on save. `UserConfigSettingsProviderTest` covers it. |

Reference material already in the tree:

- `pwiz-sharp/installer/` is a complete Inno pipeline for a .NET 10 WinForms app:
  `Setup.iss` (per-user/per-machine dialog, bundled .NET 10 desktop runtime with a
  `[Code]` filesystem check, `NoNetRuntime` second variant), `build.ps1` (stage, cache the
  runtime EXE, two ISCC passes, version stamping), `Ensure-InnoSetup.ps1` (CI bootstrap
  from the pinned GitHub release), `NOTES.md` (why WiX was abandoned: WiX 5 OSMF licensing,
  Burn's per-machine cache forcing two MSIs, fiddly prerequisite detection).
- Not relevant despite the name: `origin/Skyline/work/20260826_SkylineDailyPreviewInstaller`
  is a self-signed ClickOnce preview on the net472 csproj.
- File associations ClickOnce registered (master csproj `FileAssociation` items):
  `.sky` Skyline.Document.0 / SkylineDoc.ico, `.skyd` Skyline.Data.0 / SkylineData.ico,
  `.skyp` Skyline.Pointer.0 / SkylineDocPointer.ico.
- ISCC.exe is not installed on this machine yet (`winget install JRSoftware.InnoSetup` or
  run `pwiz-sharp/installer/Ensure-InnoSetup.ps1`).

## Design decisions (2026-09-03 discussion)

### Data folder

Skyline picks one writable **data folder** at startup and everything per-user goes there:
`user.config`, `base.config`, the user's Tools folder.

- The exe folder is the data folder only when **the current user owns it**. This is an
  ownership check, not a write probe and not an ACL walk: a user who happens to have write
  permission on a shared install (or an admin running unelevated) still keeps settings out
  of the exe folder. Only a genuinely per-user install, or an administrator running as the
  owner, writes there. The check does not need to be perfect.
- **No owner means ours.** When the owner cannot be determined (FAT32, exFAT, a network
  share or any file system without owners), assume the exe folder can be the data folder.
- Otherwise the data folder is under `%LOCALAPPDATA%` (product-named, e.g.
  `Skyline-daily`), in a subfolder named by a **hash of the exe folder path**, so two
  installations on one machine never share a data folder.
- **An existing hashed folder wins.** At startup, before the ownership check, look for the
  hashed data folder; if it exists, use it even when the current user owns the exe folder.
  This keeps a user's settings stable if ownership changes later (a shared install whose
  folder is taken over, an install moved between accounts) and makes the decision
  sticky rather than re-derived on every run.
- `UserConfigSettingsProvider.GetDefaultConfigFolder` and
  `ToolDescriptionHelpers.GetSkylineInstallationPath` (which roots the Tools folder beside
  the exe today) both move to this.
- SkylineCmd shares the same data folder and so the same `user.config`.

### Seeding and merging settings from the exe folder

When the data folder is not the exe folder and the exe folder holds a `user.config` (an
administrator seeded it, or an older per-user install left it):

1. First run: copy it to the data folder as `user.config`, and again as `base.config`.
2. Every run: if the exe folder's `user.config` differs from `base.config`, three-way
   merge per setting into the local `user.config`: master changed and local still equals
   base, take master; both changed, keep local. Then overwrite `base.config` with the
   new master. Compare length and timestamp first so an unchanged master costs nothing.
3. Merge at setting granularity only. List settings (ToolList, reports, etc.) are one XML
   string each; merging inside them is not worth attempting.
4. ClickOnce migration (`MigrateSettingsFromClickOnceInstallation`) writes into the data
   folder, and only when no `user.config` exists there. When both an admin-seeded file and
   ClickOnce settings exist, the admin file is the base and the ClickOnce values overlay
   it, since those are the user's own choices.

### Two Tools folders

A shared install has an **administrator Tools folder** (`<exe folder>\Tools`, installed by
whoever owns the exe folder) and a **user Tools folder** (`<data folder>\Tools`). Each
`ToolDescription` in `Settings.Default.ToolList` already says which menu items to add; it
gains a marker for which of the two folders the tool lives in, so paths are resolved
against the right root rather than stored absolute. Installing a tool as an ordinary user
goes to the user folder; the admin folder's tools reach every user through the seeded and
merged `user.config`.

### File associations: Inno, plus a stale-ClickOnce cleanup in Skyline

Inno registers `.sky`/`.skyd`/`.skyp` in `[Registry]` with root `HKA` (HKCU for a per-user
install, HKLM for per-machine) and `ChangeAssociation=yes`. Skyline does not register
associations itself.

One thing Skyline does handle at startup: HKCU classes override HKLM classes, so a user who
still has the ClickOnce Skyline installed has the same ProgIds under HKCU pointing at
`dfshim.dll`, and a per-machine Inno install loses to them until the old Skyline is
uninstalled. Skyline should detect HKCU entries for its ProgIds whose command runs the
ClickOnce shim and remove (or offer to remove) them. This sits next to the ClickOnce
settings migration.

### Upgrade check

`UpgradeManager` asked the ClickOnce runtime to compare against the deployment URL; on
net10 it is a `NullDeployment` stub that never finds an update. Replace with:

1. A small version manifest per channel on the web server (version, Setup.exe URL,
   SHA-256), checked at startup under the existing `CheckAtStartup` setting against
   `Install.Version`.
2. Download Setup.exe to a temp folder; verify the hash and the Authenticode signature
   (signed with the existing DigiCert KeyLocker key, same signtool arguments as
   `SignAfterPublish.bat`).
3. Run it with `/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS` plus
   `/CURRENTUSER` or `/ALLUSERS` matching the existing install (known from the data-folder
   decision). Per-machine needs elevation: start with the `runas` verb. Skyline exits
   immediately after launching so file replacement never falls back to a reboot;
   `RestartApplications` brings it back.

Other consumers of the ClickOnce URL: `LaunchBatch` (launches `.appref-ms`, port deferred
in the net8 TODO for exactly this reason), and SkylineNightly / SkylineTester, which install
daily builds through ClickOnce URLs.

### Inno script shape (differs from pwiz-sharp)

- `AppId` **not** versioned: one install slot that upgrades in place. pwiz-sharp installs
  versions side by side, Skyline must not.
- `PrivilegesRequired=lowest` + `PrivilegesRequiredOverridesAllowed=dialog`: one Setup.exe
  asks "for me" (`{localappdata}\Programs\Skyline-daily`) or "for everyone" (`{autopf}`).
- Bundle the .NET 10 desktop runtime the way pwiz-sharp does (with the `NoNetRuntime`
  variant); keep its `IsDotNetDesktopInstalled` check.
- Payload: `bin\Release\net10.0-windows` (624 files, 270 MB before stripping `.pdb`/`.xml`).
- Sign Setup.exe; wire into `build.bat`/`tcbuild.bat` as a TeamCity artifact.

## Tasks

- [ ] Data folder: owner check (no owner = usable), `%LOCALAPPDATA%\<hash of exe path>` fallback that wins once it exists, shared by `UserConfigSettingsProvider` and the Tools folder; SkylineCmd uses the same file
- [ ] Seed `user.config` + `base.config` from the exe folder; per-setting three-way merge on master change
- [ ] Point `MigrateSettingsFromClickOnceInstallation` at the data folder; define precedence over an admin-seeded file
- [ ] Two Tools folders; `ToolDescription` records which root a tool lives in; tool install goes to the user folder
- [ ] Stale ClickOnce HKCU ProgId cleanup at startup
- [x] `pwiz_tools/Skyline/installer/Setup.iss` + `build.ps1` cloned from pwiz-sharp (unversioned AppId, file associations, icons, Start Menu, launch) - 2026-09-14, see "Installer as built" below
- [ ] `build.bat --installer` step + `tcbuild.bat` artifact (call `pwiz-sharp/installer/Ensure-InnoSetup.ps1` first, warn and skip when ISCC is missing, like pwiz-sharp)
- [ ] Installer test (silent per-user install, SkylineCmd --version, uninstall, association hand-back) on the pattern of `pwiz-sharp/pwiz/test/Installer.Tests`
- [x] Version manifest format; `UpgradeManager` replacement (manifest, download, verify, silent Inno launch, exit) - 2026-09-14, `Util/InstallerDeployment.cs`, see "Update check as built" below. Nick tests manually; no automated test by request
- [ ] Server location for the manifest + installers (placeholder constants in `InstallerDeployment.CHANNELS`); signing so the download can also be checked for a signature
- [ ] LaunchBatch / SkylineNightly / SkylineTester off the ClickOnce URLs
- [ ] Signing + TeamCity artifact wiring
- [ ] End-to-end: per-user install over a ClickOnce 26.1 (settings and tools inherited); per-machine install with admin-seeded config and tools reaching a non-admin user; upgrade through the in-app check
- [ ] Retire `Executables/Installer` (WiX) and the ClickOnce publish properties

## Installer as built (2026-09-14)

`pwiz_tools/Skyline/installer/`: `Setup.iss`, `build.ps1`; `build/` and `cache/` are gitignored.
Inno Setup 6.7.3 installed per-user with `pwiz-sharp/installer/Ensure-InnoSetup.ps1` (shared, not copied).

```
pwsh -File ai/scripts/Skyline/Build-Skyline.ps1 -SourceRoot I:/git_i/sky_netinstaller -Target Skyline -Configuration Release -VendorLicenses
pwsh -File pwiz_tools/Skyline/installer/build.ps1 -SkipBuild
```

- Product from the exe in the payload (`Skyline.exe` or `Skyline-daily.exe`), version from its
  file version (26.1.1.256). Payload `bin\x64\Release\net10.0-windows` (or `bin\Release\...` from
  build.bat): 540 files / 226 MB staged, 84 files / 41 MB skipped (.pdb, XML doc beside an
  assembly, non-Windows `runtimes\`, user.config/SkylineLog.txt/Tools left by a developer run).
  Vendor DLLs stay in: Skyline ships them, unlike pwiz-sharp's on-demand loader.
- Output `Skyline-daily-Setup-26.1.1.256.exe` 106 MB (bundles the 57 MB .NET 10 desktop
  runtime) and `Skyline-daily-NoNetRuntime-Setup-26.1.1.256.exe` 49 MB. lzma2/ultra64, about
  90 s per ISCC pass on this machine.
- **Side by side decided**: one unversioned AppId per product (`Skyline`
  {DEDB22EA-0120-4DB3-A373-B86854418B5B}, `Skyline-daily` {2CE750B9-F9DC-40A5-B3C3-7FCC822DCD1D}),
  `{autopf}\<Product>`, Start Menu group "MacCoss Lab, UW" (the ClickOnce group, so shortcuts
  of both kinds sit together).
- ProgIds are per product: `Skyline.Document.0`/`.Data.0`/`.Pointer.0` for the release (what
  ClickOnce registers today), `SkylineDaily.*` for the daily, so neither uninstall removes the
  other's file types. Command `"<exe>" --opendoc "%1"`. The extension's default value is
  written without an uninsdelete flag; `[Code]` saves the previous ProgId under ours
  (`PreviousAssociation`) at `ssInstall` and puts it back at `usUninstall` if the extension
  still names ours. Verified: install over ClickOnce took `.sky` to `SkylineDaily.Document.0`,
  uninstall returned it to `Skyline.Document.0`.
- No license page (Skyline shows its own on first run), settings and installed tools are not
  removed on uninstall (only an empty `Tools` folder, which Skyline creates at startup and
  which otherwise keeps `{app}` alive).
- Verified by a silent per-user install: 545 files, Uninstall key
  `{2CE750B9-...}_is1` with `InstallLocation` ending in `\` (what `RegisteredInstallations`
  reads), installed `SkylineCmd.exe --version` and `Skyline-daily.exe` (Start Page) run on the
  machine's .NET 10, silent uninstall leaves no key, ProgId or shortcut.
- Not done: signing, TeamCity wiring, an installer test, per-machine run (needs elevation).

## Update check as built (2026-09-14)

`UpgradeManager` is unchanged except that its default `IDeployment` is now
`Util/InstallerDeployment.cs` (the `NullDeployment` stub is gone), so the existing startup check
under `UpdateCheckAtStartup`, the Help > Check for Updates item (visible again when
`IsNetworkDeployed`), `UpgradeDlg` and the `UpgradeTest` fakes all still apply.

- **Deployed?** The exe folder equals the `InstallLocation` of one of our two Inno Uninstall keys
  (HKCU = per-user, HKLM = per-machine, 64-bit view). Developer bins are never deployed.
- **Manifest** `<Product>.json`, written by `installer/build.ps1` beside the installers:
  `{ "version", "url" (relative to the manifest or absolute), "size", "sha256" }`. Channel URL
  from the matching AppId; placeholders `https://skyline.ms/installer/Skyline[-daily].json` until
  the server is chosen. `SKYLINE_UPDATE_MANIFEST_URL` overrides it for testing.
- **Check**: manifest version > assembly version. **Update**: download to `%TEMP%` through
  `HttpClientWithProgress` (progress and cancel flow through `UpgradeManager`'s LongWaitDlg),
  verify size + SHA-256. **Restart**: run the installer with
  `/SILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /RELAUNCH=1` plus `/CURRENTUSER` or
  `/ALLUSERS` (runas verb, one UAC prompt), then `Application.Exit()`. Setup.iss has a `[Run]`
  entry gated on `{param:RELAUNCH}` with `runasoriginaluser` that starts Skyline again.
- **Fallback link** on failure opens the installer URL in the browser.
- Manual test recipe: install a build, serve `installer/build/` over HTTP (e.g. a Python
  `http.server`), edit the served `Skyline-daily.json` to a higher version, set
  `SKYLINE_UPDATE_MANIFEST_URL` to its URL and start the installed Skyline.

## Open questions

- ~~Product name and data folder name for release vs daily (`Skyline` vs `Skyline-daily`), and whether they may be installed side by side (different AppIds).~~ Side by side, per-product AppIds and ProgIds (above).
- Where the version manifest lives and who publishes it (release process).
- Whether the merge should also cover the admin Tools folder contents changing (new tool dropped in by the admin) or only `user.config`.

## Findings worth keeping

- ClickOnce on .NET 5+ is publish-profile driven and cannot be produced by `dotnet publish`; see `TODO-20260825_net8_clickonce.md` for why settings did not survive updates there either (`%LOCALAPPDATA%\...\<product>_Url_<hash of install dir>\<version>` changes hash every version).
- `LocalFileSettingsProvider`'s per-launch-path hash is why a developer machine has hundreds of settings folders; `ClickOnceInstallations` searches the `Apps\2.0` store instead so only real installations are candidates.
- .NET apps run with an asInvoker manifest, so UAC file virtualization never masks a failed write to Program Files.
