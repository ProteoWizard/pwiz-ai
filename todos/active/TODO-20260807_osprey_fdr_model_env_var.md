# Demote --fdr-method to an env var, delete 'simple', and re-enable GBDT

## Branch Information
- **Branch**: `Skyline/work/20260807_osprey_fdr_model_env_var`
- **Base**: `master`
- **Created**: 2026-08-07
- **Status**: In Progress
- **GitHub Issue**: [#4543](https://github.com/ProteoWizard/pwiz/issues/4543)
  (also closes [#4491](https://github.com/ProteoWizard/pwiz/issues/4491))
- **Module**: `osprey`
- **Labels**: `osprey`, `tech-debt`
- **PR**: (pending)
- **Checkout**: `C:\proj\pwiz`

## Objective

Osprey has two configuration surfaces with distinct audiences, now stated as a rule:

- **Command-line argument = user-facing.** Product surface: documented in `--help`,
  expected to work, expected to be tested, expected to stay.
- **Environment variable = developer testing and diagnostic.** Experimental arms we
  are still evaluating, and instrumentation we use to investigate. May change or go.

`OSPREY_EXPERIMENT_AGG`, `OSPREY_PASS2_QVALUE` and the `OSPREY_GBT_*`
hyperparameters already follow this. `--fdr-method {percolator | gbdt | simple}`
does not: it presents three co-equal supported choices when only `percolator`
(linear SVM) is tested. GBDT came over from Mike's Rust implementation and was
promoted to a CLI flag **before the arg-vs-env-var rule existed**; Mike has since
described it as something he tried and set aside. It is being KEPT - it is still
worth experimenting with - but as an experimental arm, not product surface.

Three things follow:

1. **The name describes the wrong axis.** `percolator` and `gbdt` differ ONLY in the
   classifier; `PercolatorEngine.cs:390` says so outright. Both are Percolator.
2. **The flag invalidates no cache.** `FdrMethod` is absent from `SearchIdentity`,
   and `OspreyTask.ValidityKey` is only `search=...;library=...` plus the pick
   suffix. Switching arms in a warm output directory makes
   `TaskValiditySidecar.IsValid` return true, the driver skips `Run`, and the
   PREVIOUS arm's q-values are recorded as the new arm's measurement - exactly what
   `ExperimentAggValidityKeySuffix()` exists to prevent. The experimental env vars
   have that protection; the CLI flag never did. The arrangement is inverted.
3. **Nobody gated it, because a CLI flag reads as supported.** GBDT has been
   silently training a linear SVM (#4491) undetected.

## Tasks

- [ ] Fix #4491: `PercolatorScorer.RunStreamingFirstPass` (`:741`) hand-builds its
      train config and drops `UseGradientBoostedTrees`, `GbtParams`, `NThreads`.
      Use `percConfig.CloneForTrainOnly()`
- [ ] Regression test at the STREAMING altitude: drive the streaming first pass with
      the GBDT arm selected and assert a tree ensemble was actually trained. The
      existing GBDT tests build `PercolatorConfig` directly and cannot see this break
- [ ] Remove `--fdr-method` entirely (no deprecation alias)
- [ ] Move model selection to an env var following the `OSPREY_PASS2_QVALUE` pattern,
      **with a validity-key suffix** so A/B arms invalidate correctly
- [ ] Delete `simple`: `FdrMethod.Simple`, the arg-parse case, the dispatch at
      `FirstPassFdrTask.cs:1857`, and `RunSimpleFdr`
- [ ] KEEP `FdrController` - `TargetDecoyCompetition.cs:52-59` documents it as the
      shared competition primitive, deliberately not duplicated, with its own tests
- [ ] Decide the unknown-value fallback: today an unrecognized `--fdr-method` warns
      and sets `Percolator` while the dispatch `default:` falls to `RunSimpleFdr`.
      Should FAIL, not silently degrade - same family as #4491
- [ ] Mark GBDT `**Experimental.**` in `docs/07-fdr-control.md`, matching the
      existing convention for `OSPREY_EXPERIMENT_AGG` and the floor toggles
- [ ] `Build-Osprey -RunTests -RunInspection`
- [ ] `regression.ps1 -Dataset Stellar` - must be byte-identical: the default SVM
      path is untouched by this change

## Why one PR (sequencing decision)

An earlier draft proposed doing #4491 first as its own PR. Overruled by Brendan:

1. The PR mechanism has real cost - branch, CI, review, merge - and a one-line fix
   does not repay it alone. #4491 re-enables a neglected algorithm and testing
   option; it fixes nothing a user relies on today.
2. Clean up this area in one pass rather than leaving it half-migrated.

Fixing and rewiring together is also the safer order: GBDT is repaired and correctly
wired in the same change, so there is no window where a broken arm sits on the new
surface.

This does NOT remove the need for a wider review of all remaining command arguments
(the audit in #4543 lists `--fdrbench*`, `--write-pin`, `--decoy-pairing-manifest`,
`--diagnostics`, `--perf-stats` as further candidates). That pass is deliberately
follow-up, so this PR stays reviewable.

## Tripwire

`--model-diagnostics` and `--fdrbench-pass 1` force the resident first-pass pool via
`NeedsResidentPool`, and `hpc-merge` / `fdrbench-pass1` are **pinned token strings**
in `ResidentPaths.KNOWN_UNFIXED` with `ResidentPoolGuardTest` asserting the exact
list. Anything moving those flags must keep the tokens consistent, or the
resident-pool guard names a flag that no longer exists - the same failure #4535 was
about.

## Regression Test

- **Test name**: (filled in once written)
- **Test project**: Osprey.Test
- **Fails on master**: (pending - must be verified RED before the fix)
- **Passes on fix**: (pending)

The GBDT wiring test is the FIRST deliverable, not the last: write it, watch it fail
on master (proving it can see the #4491 break), then fix. The existing GBDT tests
pass today despite the bug, which is precisely the gap being closed - they test the
classifier, not the path that reaches it.

The `simple` deletion needs no new test. `regression.ps1 -Dataset Stellar` must stay
byte-identical, since the default SVM path is untouched.

## Progress Log

### 2026-08-07 - Session Start

Branch created off master (`dce8841689`, the #4540 rename merge). Follows directly
from the #4535 work, which is what surfaced the `--fdr-method` surface question.
