# net8 ClickOnce installer: publish, sign and upgrade the .NET 8 Skyline-daily

## Branch Information
- **Checkout**: `I:\git_i\sky_net8_clickonce`
- **Branch**: `Skyline/work/20260825_Net8ClickOnce`, based on
  `Skyline/work/20260612_net8_port` (the port itself, PR #4619). 9 commits plus one
  intentional merge of `origin/chambem2/pwiz-sharp`.
- **PR**: #4620, **draft**, stacked on #4619 so the diff shows only the installer work
- **Created**: 2026-08-25
- **Status**: pushed and green (Release solution build, CodeInspection,
  TestUserConfigMigration). Waiting on Brendan to verify DigiCert signing.
- **Module**: `skyline`

## Why

The SDK conversion dropped the ClickOnce settings the legacy csproj carried inline, so the
net8 Skyline had no way to ship. .NET 5+ ClickOnce is publish-profile driven and cannot be
produced by `dotnet publish` at all - only MSBuild implements the publish protocol - so the
whole path had to be rebuilt rather than ported. Two things then turned out to be broken in
ways that only show up in an *installed* app, not in a build: the deployment payload, and
settings migration across an update.

## What was done

| SHA | What |
|---|---|
| `91835ddc5` | ClickOnce publishing for net8: `Publish-ClickOnce.ps1` + `ClickOnceProfile.pubxml`, ApplicationVersion stamped from the git-date version, file associations and icons restored |
| `f03ef25ea` | Deployment payload fixed so the installed app works |
| `e86e26016` | setup.exe carrying the .NET 8 Desktop Runtime prerequisite, plus an install page |
| `73806d4e1` | Manifest named 103 files twice, which the sxs parser rejects outright |
| `e8bbadcb9` | ZIP-relative publish (no `deploymentProvider`) so the net472 -> net8 upgrade could be tested from an extracted folder |
| `a214c449e` | `UserConfigMigrator` - net8 updates were starting from default settings |
| `762abd037` | Official location restored; `-KeyLocker` added for the University of Washington certificate |
| `f27c972f8` | Removed the `SkylineVersionOrdinal` override point once nothing set it |
| `1ad0b6258` | Removed `SkylineDailyPreviewSelfSigned.cer`, which nothing referenced |

## Findings worth keeping

### Settings do not survive an update on net8, and never would have

.NET Framework's `ConfigurationManager` knows about ClickOnce and keeps user.config in the
deployment's ClickOnce **data directory**, which ClickOnce itself copies forward on the first
run after an update. .NET 8 dropped that awareness entirely and uses the ordinary desktop
path instead:

    %LOCALAPPDATA%\<company>\<product>_Url_<hash of the install directory>\<version>\user.config

Measured on one machine after a net472 -> net8 upgrade:

| Build | Where user.config landed |
|---|---|
| net472 26.1.1.238 | `Apps\2.0\Data\...\skyl..tion_a58fda...\Data\26.1.1.238\` |
| net8 26.1.1.237 | `pwiz\Skyline-daily_Url_`**`x2ysvltp...`**`\26.1.1.237\` |
| net8 26.2.1.237 | `pwiz\Skyline-daily_Url_`**`ch4sk0ht...`**`\26.2.1.237\` |

Two separate failures fall out. The net472 settings are in a directory net8 never looks at;
and because the folder name hashes the **install directory**, which every ClickOnce version
changes, two net8 versions get two different hashes - so `Settings.Default.Upgrade()`, which
only scans sibling *version* folders under the same hash, finds nothing either. net8 -> net8
updates would have lost settings too, not just the framework switch.

`UserConfigMigrator` copies the previous file forward from either source, taking the highest
version below the running one (Upgrade() semantics), requiring the file to contain
`pwiz.Skyline.Properties.Settings`, and only when the app is ClickOnce-installed - so a build
run from its own output directory keeps its own settings and TestRunner is excluded.

ClickOnce had in fact done its job: the net8 deployment's data directory already held the
migrated net472 user.config. Nothing was reading it.

### deploymentProvider decides where an installed client goes

`UpdateUrl`, falling back to `InstallUrl` then `PublishUrl`, becomes `<deploymentProvider>`
in the .application, and it **wins over the URL the manifest was actually fetched from**.
ClickOnce has no relative install URL; blanking both (which
`Microsoft.Common.CurrentVersion.targets` only honours because `UpdateEnabled` is false)
produces a deployment with no provider that installs out of whatever folder setup.exe was run
from. That is how the upgrade was tested from a ZIP. `IsWebBootstrapper` is the matching
switch for setup.exe's own `ApplicationUrl` - true with a blank InstallUrl bakes a `file://`
path to the publishing machine into setup.exe.

### The official certificate is a file at a fixed path, not an environment variable

`pwiz_tools/Skyline/Jamfile.jam`:

    path-constant CRT_PATH : "$(SKYLINE_PATH)/University of Washington (MacCoss Lab).crt" ;
    constant CRT_KEY     : "key_637015839" ;

The certificate is dropped in by hand (untracked, and not gitignored either). The **private
key is not a file at all** - it is in the DigiCert KeyLocker cloud HSM, reachable only through
`/csp "DigiCert Signing Manager KSP"` + `/kc <key>`. The certificate's presence is the on/off
switch: Jam generates `SignAfterPublishKey.bat` only `if [ path.exists $(CRT_PATH) ]`, and the
csproj `AfterPublish` target runs only if that bat exists.

None of that chain worked for net8, for four independent reasons: the bat is generated by Jam
and the net8 publish never runs Jam; the publish folder in the csproj command is
`bin\$(Platform)\$(Configuration)\app.publish` while net8 publishes to `publish\`; the app
manifest is `<name>.dll.manifest`, not `<name>.exe.manifest`; and mage.exe cannot update it.

Osprey's `OSPREY_SIGN*` environment variables are **not** a usable model - they offer a PFX or
`signtool /a`, neither of which reaches the HSM key. Already recorded as wrong for KeyLocker in
`todos/backlog/TODO-release_process_unification.md`.

### dotnet-mage, verified

Verified against a self-signed certificate so that Brendan's run isolates the KSP alone:

* dotnet-mage 10.0.0 signs both net8 manifests and preserves the deployment identity
  (name / version / publicKeyToken / msil / culture) and the `<deployment>` element.
* `-update` **re-hashes the payload it lists**: appending 10 bytes to `Launcher.exe` moved the
  recorded size from 17848 to 17858. So PEs must be signed *before* the application manifest,
  and the application manifest before the deployment manifest that hashes it - the same order
  `SignAfterPublish.bat` uses for net472.
* `-Verify` is **broken** in 10.0.0: "Internal error, please try again. Object reference not
  set to an instance of an object." on manifests it has just signed successfully. Do not add a
  verify pass.

Still unknown, and the reason for the draft PR: whether the KSP can be driven through
`signtool /csp` + `/kc` and `dotnet-mage -CryptoProvider` + `-KeyContainer`.

### Publishing mechanics

The net472 publish must be driven off `Skyline.sln` (`-t:Skyline:Publish`), not the csproj -
the csproj route forces `Platform=x64` onto `SkylineTool`, which is AnyCPU in the solution, and
that breaks both its output path and a NuGet RID check. MSBuild's `AfterPublish` `Exec`
inherits the *shell's* working directory, not the project directory, so
`SignAfterPublishSelfSigned.bat` was not found; that `Exec` should use `$(ProjectDir)`.

## Remaining

- [ ] **Brendan: verify DigiCert signing.** `Publish-ClickOnce.ps1 -KeyLocker`, cert dropped
      into `pwiz_tools\Skyline\`. Preflights cert/dotnet-mage/signtool before building; nothing
      uploads. Caution: a KeyLocker-signed build carries the **real Skyline-daily identity**, so
      installing it upgrades a production Skyline-daily; and signatures are metered, so the
      script prints the operation count before spending it.
- [ ] **net472 -> net8 upgrade verified from an installed client.** `UserConfigMigrator` is
      covered by `TestUserConfigMigration` at unit level only; the actual install path has never
      been exercised end to end.
- [ ] `/code-review max` before the PR leaves draft - not yet run.
- [ ] Decide whether the ZIP-relative publish deserves a `-ZipRelative` switch. It currently
      exists only in `e8bbadcb9`; restoring the official URLs removed it from the tree, so the
      upgrade-from-a-folder test cannot be repeated without editing the profile.

## Defects found but not fixed

- **`Publish-ClickOnce.ps1 -SkipBuild` is broken.** `-p:NoBuild=true` fails with
  `MSB3094: "DestinationFiles" refers to 2 item(s), and "SourceFiles" refers to 1 item(s)` in
  `_CopyFilesToPublishDirectory`. Worse, the script clears `publish\` *before* the publish runs,
  so the failure destroys the previous output. Fix `NoBuild` or drop the switch.
- **CodeInspection mutates ClickOnce publish output.** Run with a `publish\` folder present it
  reports BOM failures for `Skyline-daily.dll.config`, `BaseDataAccess.dll.config` and two Sciex
  `.config` files *and strips the BOMs*, invalidating the manifest hashes. `publish\` is
  gitignored but CodeInspection walks the filesystem. It should skip that directory.
- **The net8 tree does not compile without `-VendorLicenses`**
  (`SpectrumList_LockmassRefiner` unguarded in `ProteowizardWrapper.PwizSharp`), and the
  **Debug** configuration additionally fails on a missing
  `pwiz-sharp\...\BlibBuild\bin\Debug\net8.0\runtimes\win-x64\native\msparser.dll`. Release
  works. Both predate this branch.

## Deferred to a separate work item

Where user.config lives, making SkylineCmd share Skyline's settings file, and reworking the
Tools folder so an administrator install's tools reach ordinary users. All three are real -
SkylineCmd genuinely uses a different user.config than Skyline, and admin-installed tools land
in a machine-wide folder while the menu entries stay in a per-user `Settings.Default.ToolList` -
but none of them are caused by the .NET 8 port, so they were cut from this branch.
