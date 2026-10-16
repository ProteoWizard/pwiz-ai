# TODO-pwiz_translation_expansion.md - translation tooling and reviewer process for all of pwiz, not only Skyline

## Branch Information
- **Branch**: (not started) - one branch per work item below
- **Base**: `master`
- **Module**: `pwiz` / `skyline` (DevTools)
- **Created**: 2026-10-16 (Brendan, while documenting the Osprey translation round)

## Why
Until the .NET 10 move, only the C# applications were localized; msconvert, the `pwiz/` library and
BiblioSpec were C++ and never translated. PR #4658 (2026-10-07) retired the C++ tree, so the tools
in the ProteoWizard installer can now be translated through the same RESX pipeline as Skyline.
Background and procedure: `ai/docs/translation-drafting-guide.md` ("Why there is more to translate
now") and `ai/docs/translation-guide.md`.

Target set, in rough priority order (most-used tools first): Osprey (drafted, #4752), BiblioSpec,
CarafeSharp, msconvert (`pwiz_tools/Commandline` + the `pwiz/` library text it surfaces),
MSConvertGUI, SeeMS.

## The open question this depends on
**Will the ja / zh reviewers accept Claude drafts as their starting point, or will they want the
professional translation company back?** That question is untested, and the reviewers may well
push back. Every work item below makes sense either way: the company's deliverable and Claude's
are the same localization CSVs. What the answer changes is the cost of each new project, and
therefore how fast the target set moves.

Test it before scaling up:
1. Send the reviewers the Osprey reviewer CSVs and the blind A/B grading sheets (Claude vs
   professional, unlabeled, "accept / minor edit / wrong") produced by
   `TODO-20260928_osprey_resx_translation.md`. As of 2026-10-16 those files are only in
   Brendan's machine-local session folder (`ai/.tmp/sessions/20260928-resxtr/reviewer-package/`,
   `eval/blind-grading.*.csv` + `blind-grading-key.*.csv`). Move them somewhere durable first.
   The reviewer CSVs are stale: they were built when master had 885 Osprey English resources,
   and it has 797 (2026-10-16). Regenerate them with `ai/scripts/Translation/reviewer_package.py`
   from current master before sending. The blind grading sheets are Skyline holdout strings and
   can be sent as they are. Never commit either to pwiz-ai, because the repo is public.
2. Record the outcome here: grading results per language, the reviewers' own comments, and their
   edit rate on the Osprey drafts.
3. Decide per language (ja and zh may differ: in the holdout, zh reviewers changed 24/521 professional
   drafts, ja reviewers 116/520): Claude drafts → reviewers, or company → reviewers with Claude used
   only for consistency checking.

## Tooling state on master (measured 2026-10-16)
- **The quickbuild entry points are gone.** #4658 deleted `ResourcesOrganizer/Jamfile.jam` and
  `TutorialLocalization/Jamfile.jam`, and there is no `quickbuild.bat`. The targets
  `IncrementalUpdateResxFiles`, `FinalizeResxFiles`, `GenerateLocalizationCsvFiles` and
  `ImportLocalizationCsvFiles` no longer exist. The `scripts\*.bat` files they called still work,
  but they need `ResourcesOrganizer\bin\Release\ResourcesOrganizer.exe`, which the Jamfile used to
  build (`dotnet build ... /p:Configuration=Release;OutDir=<that dir>`). No `ai/scripts` wrapper
  covers DevTools projects.
- **Coverage is all of `pwiz_tools` minus an exclude list, not an opt-in list.** `MakeResourcesDb.bat`
  adds every `.resx` under `pwiz_tools` except a hardcoded list that includes `msconvertgui`,
  `seems`, `bumbershoot`, `skylinebatch`, `autoqc`, and others. `UpdateResxFiles.bat` adds
  `pwiz_tools\Osprey` through `EXTRA_EXCLUDE`. The top-level `pwiz/` library is outside `pwiz_tools`
  and is never scanned. BiblioSpec, CarafeSharp and Commandline would be picked up automatically as
  soon as they have `.resx` files.
- **One baseline for everything.** `pwiz_tools/Skyline/Translation/LastReleaseResources.db` is
  keyed to Skyline's release, so it cannot record "reviewed" for a project with a different
  release cadence. Osprey is excluded from the update targets for that reason.
- **Resources today**: BiblioSpec 0 `.resx` (70 `.cs`), Commandline 0 (15), `pwiz/` 0 (462),
  CarafeSharp 1 (`CarafeCommandArgUsage.resx`), MSConvertGUI 4 and SeeMS 16 (WinForms designer
  resx, excluded, no `.ja`).
- **Checks are per project.** Skyline has `TestData/LocalizedResourcesTest.cs`, Osprey has
  `Osprey.Test/OspreyLocalizedResourcesTest.cs`. A shared version in CommonUtil's tests or
  `Shared/` would avoid a third and fourth copy.
- **Shipping**: `scripts/installer/build.ps1` builds MSConvertGUI and SeeMS. Check that `ja\` and
  `zh-Hans\` satellite folders reach the installer once those tools have translations.
- `DevTools/TutorialLocalization` is Skyline tutorials only, which is fine: the other tools have no
  translated tutorials.

## Work items
1. **Restore a runnable entry point** for the four ResourcesOrganizer operations: an
   `ai/scripts` wrapper (or a `.ps1` beside the bats) that builds the exe and runs the
   operation. Then update `ai/docs/translation-guide.md`, which still documents quickbuild.
2. **An opt-in project list** replacing the hardcoded excludes: one checked-in file naming the
   translated projects, read by `MakeResourcesDb.bat`. It should cover `pwiz/` as well as
   `pwiz_tools`, with per-project baseline handling, either per-project rows in the db or a
   project column, so each project's "reviewed" state follows its own release.
3. **A shared localized-resources test** that each project's test assembly calls.
4. **Per project**, in the target order: move the text to RESX (follow
   `TODO-20260926_osprey_resx.md`), opt in, draft (or send to the company, per the decision
   above), review, import, ship satellites.
5. Nick owns ResourcesOrganizer. Agree items 1-3 with him before starting (#4737 was the last thread).
