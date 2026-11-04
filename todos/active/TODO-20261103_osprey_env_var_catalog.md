# TODO-20261103_osprey_env_var_catalog.md

## Branch Information
- **Branch**: `Skyline/work/20261103_osprey_env_var_catalog`
- **Base**: `master`
- **Created**: 2026-11-03
- **Status**: In Review (PR open; TeamCity Perf/Regression not yet run - parent session queues it)
- **GitHub Issue**: (none - from backlog `TODO-osprey_env_var_cataloging.md`, folded in below)
- **Module**: `osprey`
- **PR**: [#4983](https://github.com/ProteoWizard/pwiz/pull/4983)
- **Worktree**: `C:\proj\wt-envvar` (night-session agent worktree, round 2 wave B)

## Objective

Catalog Osprey's OSPREY_* environment variables the way `CommandArg` catalogs CLI arguments:
an `EnvVar` declaration beside every read (group and description required by the
constructor), `--help-env` printing the table grouped by kind, startup logging every set
switch, a source-scan test forbidding raw environment access, and an out-of-set value on a
listed-value switch refused at startup. Cataloging only: no switch becomes a CLI argument.

## Design (as built)

- `Osprey.Core/EnvVar.cs`: `EnvVarGroup` { behavior, allowance, performance, harness,
  diagnostic }; `EnvVar(name, group, description)` with `ValueExample`, `Values`,
  `AcceptsValue`, `DefaultValue` (the cataloging members of `pwiz.Common.CommandLine.ArgumentBase`);
  `Value` is the ONLY environment read in Osprey (test overrides first, then the process).
  `OverrideVariables` and the OSPREY_* name scan moved here from `OspreyEnvironment`.
  `EnvVarCatalog.Collect(assembly)` finds every `static EnvVar` field by reflection in the
  root assembly and every `Osprey*` assembly it references, so declarations stay next to the
  read and no central list exists to forget. Duplicate names throw.
- Declarations (97) in `OspreyEnvironment` (54), `OspreyFileDiagnostics` (38),
  `FdrDiagnostics` (3), `SpectralScorer` (1), `ParquetScoreCache` (1). Each reader keeps its
  exact interpretation (IsOne / IsSetAndNotZero / IsNotZero / int / double) with the helper
  retyped from `string name` to `EnvVar`. The `KnownVariables` set (98 names, #4825) is gone.
- `Osprey/EnvVarUsage.cs`: the catalog (lazy), `--help-env [ascii|unicode]` rendered with
  `ConsoleTable` in `--help`'s format, one table per group; the unknown-name refusal with a
  "did you mean" suggestion (edit distance <= 3) and a pointer to `--help-env`; the
  `Environment switches: NAME=value, ...` startup line (absent when nothing is set).
- `Program`: unknown-name ERROR (kept), then the generic listed-value check
  (`EnvVarCatalog.ValueErrors`), then the provenance line. `OSPREY_EXPERIMENT_AGG` unrecognized
  turned from a warning (ran `max`) into a startup error.
- OSPREY_DIAGNOSTICS bundle: the force-on list moved beside its declarations
  (`OspreyFileDiagnostics.FORCED_DUMP_BUNDLE`) and sets through `EnvVar.SetInProcess`.
- `CodeInspectionTest.TestEnvironmentReadThroughEnvVar` replaces
  `TestOspreyVariablesAreRegistered`: no `Environment.Get/SetEnvironmentVariable(s)` outside
  `Osprey.Core/EnvVar.cs` (no exemption tag); every whole `"OSPREY_X"` literal in production code
  is catalogued; every entry has a description; one entry from each reading assembly is found;
  `--help-env` lists every entry whole.

## Decisions Brendan may revisit

1. **Unknown OSPREY_* name stays an ERROR, not the warning the backlog TODO and the brief
   proposed.** The backlog text (2026-08-29) predates #4825 (2026-10-12), which made it an error
   deliberately, replacing four per-switch refusals of retired names. Downgrading would relax a
   gate added on purpose; the conservative option was to keep it and add the suggestion.
2. **Descriptions are NOT RESX-bound.** `docs/20-command-line.md` ("Localization") already rules
   that environment variable names and diagnostics reached only through an OSPREY_* setting are
   `@"..."` untranslated text, and `CodeInspectionTest.TestResourcesUseUserVocabulary` bans
   `OSPREY_[A-Z_]+`, "Stage N", "entries" and the like from English resource values - so the
   catalog's own vocabulary could not live in a resource. Only the `--help-env` argument's own
   `--help` line is a resource (`OspreyCommandArgUsage._help_env`).
3. **No shared base extracted from `ArgumentBase`.** "CommandArg-shaped" was taken as mirroring
   its cataloging members, not refactoring `pwiz_tools/Shared/CommonUtil/CommandLine` (Skyline's
   too) for a base nothing would iterate polymorphically.
4. **The four `IsSet` flags now read `IsSetAndNotZero`** (OSPREY_EXIT_AFTER_CALIBRATION,
   OSPREY_LOG_COASSIGN_ALLOC, OSPREY_MDIAG_COASSIGN_ONLY, OSPREY_LIBRARY_LOAD_ONLY): `=0` used to
   turn them ON, the #4673 trap, and the catalog documents every flag as `0|1`. The dump flags
   keep their exact `=="1"` reading.
5. **Listed-value check applies to every switch that lists values**, not only behavior ones:
   PASS2_QVALUE, FDR_MODEL, DETERMINISTIC_MATH (their own messages first), EXPERIMENT_AGG,
   SERIAL_READ_SCOPE (`file|process`; `file` is new spelling for the per-file default),
   STUB_IDENTITY (`0|1|2`). On/off flags and numbers are not validated (the guide's "do not
   harden env vars" doctrine; only arm-mislabeling values are refused).
6. **Graduation lifecycle (experimental | promoted) not added.** The backlog listed it as a
   later idea; it is not needed for the catalog and would be a new concept to review.
7. The `Pass2FdrSidecar` "Recognized modes" message the backlog named is already gone on master
   (the PASS2_QVALUE error now names both remaining modes) - nothing to fix.

## Tasks

- [x] Read backlog TODO, code, existing registry (#4825) and tests
- [x] EnvVar / EnvVarCatalog / EnvVarUsage, declarations at every read
- [x] `--help-env`, startup provenance line, generic listed-value check, EXPERIMENT_AGG error
- [x] Source-scan test, CommandLineErrorTest cases (misspelling suggestion, bogus listed values)
- [x] docs/20-command-line.md (option row, Environment variables section)
- [x] Build-Osprey -RunTests -RunInspection green (649/649, 0 inspection warnings)
- [x] regression.ps1 -Dataset Stellar (golden unchanged)
- [x] /code-review medium, triage
- [x] Commit, push TODO, open PR

## Progress Log

### 2026-11-03 (night session, agent B)
- Implemented the design above. Manual checks: `OSPREY_PASS2_QVALUES=1` -> "did you mean
  OSPREY_PASS2_QVALUE?"; `OSPREY_SERIAL_READ_SCOPE=bad` -> refused; `OSPREY_LOG_MEMORY=1
  OSPREY_SERIAL_READ_SCOPE=process` -> `Environment switches: OSPREY_LOG_MEMORY=1,
  OSPREY_SERIAL_READ_SCOPE=process`.
- Gates: `Build-Osprey.ps1 -RunTests -RunInspection` 649/649, 0 warnings
  (`ai/.tmp/sessions/20261103-agentB/gate3.log`, after review fixes `gate4.log`);
  `regression.ps1 -Dataset Stellar` PASS on 7e6a27bd3c - mode1 vs golden, 1c, 4, streamed join, 6
  (`ai/.tmp/sessions/20261103-agentB/regress-stellar.log`). The review-fix commit is output-neutral
  (a trim in a timing switch's reader, a hoisted diagnostic read, docs, a test regex) and was
  gated by the unit tests only.
- Help pages `Documentation/Help/{en,ja,zh-Hans}/CommandLine.html` regenerated by
  `TestCommandLineHelpDocumentation` for the new argument and committed.

### /code-review medium (10 findings) - triage
Fixed:
- SERIAL_READ_SCOPE check trimmed the value but the reader did not (`'process '` passed and ran per-file).
- Catalog walk: `GetTypes()` now tolerates `ReflectionTypeLoadException` (an optional runtime's
  missing dependency must not stop startup).
- XCorr hot path read OSPREY_DIAG_XCORR_SCAN per call (pre-existing; hoisted to a static now that
  the line was touched).
- Stale docs on ExperimentAggUnrecognized / MEAN_BEST_N_MAX ("warns").
- ValueError with no Values fell back to a null ValueExample; now shows Usage.
- Source scan also catches `ExpandEnvironmentVariables` and calls without the `Environment.` prefix.
Dropped:
- Diagnostics bundle under test overrides writes the real environment and is never undone:
  pre-existing (it always used SetEnvironmentVariable); production has no overrides.
- Dump flags read exactly `1` while other flags read "not 0": pre-existing readers, kept exactly
  (decision 4); both are documented as `0|1` and the guide's doctrine is not to harden env vars.
- Two validation mechanisms (specific + generic) duplicate accepted sets: the specific messages are
  fuller and tests assert them; consolidating is a simplification beyond this change.
- STUB_IDENTITY refuses `01` / `+1` that int.TryParse accepted: a developer switch; listed values are
  the documented arms.
- `using static System.Environment`: no such use; the widened regex covers the bare call anyway.

### Coordination
- Item 2 of this wave (parity rows, branch `Skyline/work/20261103_osprey_parity_rows`) deletes
  several switches declared here (A5, A9, A14-A16). The two PRs touch the same declarations in
  `OspreyEnvironment.cs`; whichever merges second resolves by deleting the EnvVar along with its
  reader.
- #4986 (parity rows) merges AFTER this PR. It retires OSPREY_RELEASE_LIBRARY_FRAGMENTS,
  OSPREY_LOESS_CLASSICAL_ROBUST and OSPREY_BLOCK_READ_GATE and sets STUB_IDENTITY to `1|2`. Not
  done here; in the catalog that edit is: delete each `ENV_*` declaration with its reader, and
  change STUB_IDENTITY's `Values` to `{ "1", "2" }`. The 2026-11-04 merge resolution touched only
  the GBT block near DETERMINISTIC_MATH, none of those four declarations.

### 2026-11-04 (agent B2) - merged master in
- `git merge origin/master` (0bec7caeef) as merge commit 3f5c75a1f9, pushed. Master since the
  branch point: #4968, #4974, #4985, #4987, #4989, #4990, #4991 (#4969 merged into a feature
  branch, not master, so it is not in this merge).
- One conflict, `Osprey.Core/OspreyEnvironment.cs`, from #4968 (opt-in out-of-fold scoring and
  two-round GBDT first-pass training). It added two raw reads and their KnownVariables names:
  - `OSPREY_GBT_OOF` -> `ENV_GBT_OOF`, group behavior, flag (`0|1` shown, no listed values, so no
    new startup check); reader unchanged: `ParseIntOrNull(ENV_GBT_OOF) == 1`.
  - `OSPREY_GBT_PREFILTER_SIZE` -> `ENV_GBT_PREFILTER_SIZE`, group behavior, `<N>`, 0/unset off;
    reader unchanged: `Math.Max(0, ParseIntOrZero(ENV_GBT_PREFILTER_SIZE))`.
  - Descriptions from #4968's doc comments and PR body (not keyed vs keyed, resume retrains,
    second-pass still fold mean, memory cost, projection path ignores it). Master's KnownVariables
    hunk dropped (the catalog replaces it). The `ParseInt*` helpers have the same bodies as master's.
- Every other file the merge touched: no new raw environment access (grep of the master-side diff
  for Get/SetEnvironmentVariable, ExpandEnvironmentVariables and `"OSPREY_` literals).
- Gates: `Build-Osprey.ps1 -SourceRoot C:/proj/wt-envvar -Configuration Debug -RunTests
  -RunInspection` 651/651, 0 inspection warnings, incl. TestEnvironmentReadThroughEnvVar
  (`ai/.tmp/sessions/20261104-agentB2/gate2.log`; `gate1.log` was an InspectCode internal CLR
  crash 0x80131506, a tool fault, passed on retry). `regression.ps1 -Dataset Stellar` PASSED,
  mode1 vs golden PASS (`ai/.tmp/sessions/20261104-agentB2/regress-stellar.log`). `--help-env`
  lists both new switches under Behavior (`ai/.tmp/sessions/20261104-agentB2/help-env.txt`).

## Folded in: the backlog TODO (TODO-osprey_env_var_cataloging.md, raised 2026-08-29)

The idea, in Brendan's words: *"We have created a 2-level system for controlling Osprey behavior
and relegated what we feel are most likely debugging switches to env vars, but they are extensive
and could use better cataloging since we have decided to keep them."* It earned its place in the
2026-08-29 session, where a golden-moving defect closed in one cycle once `OSPREY_DUMP_RESCORED`
was found - by being told about it, not by any doc. Design points it set, all honored above:
registration next to the read; cataloging only, never promoting a switch to an argument; group
and description STRUCTURAL (constructor), so only the source scan needs a test; no runtime
"unknown name" for code (an unregistered read is a compile error), the only unknown being a
user's shell variable; the namespace claim (`OSPREY_*` is ours) decided deliberately; a value
typo on a behavior switch is an error (Mike's `transfer-complete`). Its open question - is there
a description check for CommandArgs? - is moot here: descriptions are constructor arguments.
