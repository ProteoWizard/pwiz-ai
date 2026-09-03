# TODO-20260903_Net10Installer.md

## Branch Information
- **Checkout**: `C:\git\sky_netinstaller`
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
- [ ] `pwiz_tools/Skyline/installer/Setup.iss` + `build.ps1` cloned from pwiz-sharp (unversioned AppId, file associations, icons, Start Menu, launch)
- [ ] Version manifest format + server location; `UpgradeManager` replacement (manifest, download, verify, silent Inno launch, exit)
- [ ] LaunchBatch / SkylineNightly / SkylineTester off the ClickOnce URLs
- [ ] Signing + TeamCity artifact wiring
- [ ] End-to-end: per-user install over a ClickOnce 26.1 (settings and tools inherited); per-machine install with admin-seeded config and tools reaching a non-admin user; upgrade through the in-app check
- [ ] Retire `Executables/Installer` (WiX) and the ClickOnce publish properties

## Open questions

- Product name and data folder name for release vs daily (`Skyline` vs `Skyline-daily`), and whether they may be installed side by side (different AppIds).
- Where the version manifest lives and who publishes it (release process).
- Whether the merge should also cover the admin Tools folder contents changing (new tool dropped in by the admin) or only `user.config`.

## Findings worth keeping

- ClickOnce on .NET 5+ is publish-profile driven and cannot be produced by `dotnet publish`; see `TODO-20260825_net8_clickonce.md` for why settings did not survive updates there either (`%LOCALAPPDATA%\...\<product>_Url_<hash of install dir>\<version>` changes hash every version).
- `LocalFileSettingsProvider`'s per-launch-path hash is why a developer machine has hundreds of settings folders; `ClickOnceInstallations` searches the `Apps\2.0` store instead so only real installations are candidates.
- .NET apps run with an asInvoker manifest, so UAC file virtualization never masks a failed write to Program Files.
