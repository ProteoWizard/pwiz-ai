# osprey: Stage 7 report generation and pass-2 collection log nothing for up to 151 s at a time

## Branch Information
- **Branch**: `Skyline/work/20260814_osprey_stage7_progress_reporting`
- **Base**: `master` (rebased onto `ebc7e0c4f3`)
- **Created**: 2026-08-14
- **Status**: In Progress
- **GitHub Issue**: [#4571](https://github.com/ProteoWizard/pwiz/issues/4571)
- **Module**: `osprey`
- **Other labels**: `tech-debt`
- **PR**: (pending)

## Objective

Four steps in Stage 7 / pass-2 collection run silent for 30-151 s at a time on an 82-file
run. This is an **observability** defect, not a throughput one: 373-523 s is ~1.7% of an
8.5 h run, but nobody watching can distinguish "working" from "hung" for up to two and a
half minutes, and any liveness watchdog has to be tuned above the largest gap, which is far
too coarse to catch a real stall.

The codebase already has the idiom — `ProgressReporter` with `IO_INTERVAL_SECONDS`, as used
by `Collecting pass-2 survivors from 82 file(s)... 100%` and, since #4558, by
`Peak co-assignment: scanning 1st-pass sidecars over 82 file(s)`. These four sites simply do
not use it. The work is bounded and countable at every site (protein groups, files,
spectra), so each is a progress block over a known total, not a spinner.

## Two independent 82-file reproductions

The issue was filed off the 2026-08-12 run. The 2026-08-14 run on master `012816cc53`
reproduces all four, confirming they are pre-existing and not specific to one build.

| gap | 08-12 | 08-14 | last line before the silence | what runs during it |
|---|---|---|---|---|
| A | **151 s** | **125 s** | `6096 protein groups pass 1.0% protein FDR` | Stage 7 report prep, before the blib write. Managed memory FLAT across the gap (37.7 -> 37.7 GB) => CPU-bound, not GC |
| B | **141 s** | **130 s** | `Released library fragments for 0 of 6324700 entries (...)` | pre-work ahead of `Collecting pass-2 survivors from 82 file(s)...`; the collection itself already reports |
| C | **56 s** | **71 s** | `[ENTRAPMENT] Dropped 19279 unmatched entrapment peptides (...)` | finalizing the `--model-diagnostics` report |
| D | **37 s** | **47 s** | (blank) | writing 51,597 library spectra to `out.blib` |
| | **385 s** | **373 s** | | (the 5th gap, 138 s, was #4558's and is now CLOSED) |

Movement between the two runs is run-to-run noise (two shrank, two grew); the gaps are the
same, in the same places, all inside `SecondPassFDR`'s final ~25 minutes.

Evidence on disk:
* `D:\test\Pilot-MTG-Tissue-May2026\Astral-DIA\runs\seaad-82files-libdecoy-r1.0-protein-compact-20260814_121043\run.log`
* `ai/.tmp/perfviz-20260814-final.txt`, `ai/.tmp/perfviz-0812-baseline.txt`
* `ai/.tmp/seaad-20260814-RESULTS.md` (full harvest of the 08-14 run)

## Tasks

- [ ] Locate the four silent regions in `SecondPassFdrTask` / Stage 7 report path / blib write
- [ ] Site A — Stage 7 report preparation after protein-FDR
- [ ] Site B — pre-work ahead of pass-2 survivor collection
- [ ] Site C — `--model-diagnostics` report finalization
- [ ] Site D — blib spectrum write (51,597 spectra)
- [ ] Confirm each new report is a bounded progress block over a known total, matching the
      existing `ProgressReporter` / `IO_INTERVAL_SECONDS` idiom
- [ ] Verify output byte-identical: `pwiz_tools/Osprey/regression.ps1 -Dataset All`
- [ ] Build + tests + zero-warning inspection (`Build-Osprey.ps1 -RunInspection -RunTests`)
- [ ] `/code-review max` before opening the PR
- [ ] Acceptance run (see below)

## Regression Test

- **Test name**: (see rationale — no unit test)
- **Test project**: n/a
- **Fails on master**: n/a
- **Passes on fix**: n/a

**Why no unit test.** The issue's own acceptance criterion is a property of a full 82-file
run — `perfviz.py` reporting `gaps >= 30s : 0` — and the gaps only appear at that scale
(the regression datasets complete these stages in seconds, so there is no silence to
observe). A unit test asserting "a `ProgressReporter` was constructed" would pin the
implementation rather than the behaviour and would pass even if the reporter were scoped to
the wrong half of the work, which is exactly the defect #4558 hit at this same site.

The real gate is therefore the **acceptance run**, and it is a measurable gate, not a
review judgement: `perfviz.py` prints `gaps >= 30s : N <-- OVER THRESHOLD` directly.

**This means the PR cannot be honestly closed without an 82-file run (~8.5 h).** Do not
report the issue fixed on local-dataset evidence alone. If the PR must go up before that
run completes, say so explicitly in the PR body rather than implying the gate passed.

## Progress Log

### 2026-08-14 - Session Start

Branch created off `ebc7e0c4f3`. Second 82-file reproduction captured from the overnight
run on master `012816cc53` (8 h 43 m, clean exit) — all four gaps present, 373 s total.
The fifth gap from the original report (138 s, experiment-level peak co-assignment) is
**confirmed closed** by #4558: that run shows `Peak co-assignment: scanning 1st-pass
sidecars over 82 file(s)...` where the silence used to be, and `perfviz.py` no longer
lists it.
