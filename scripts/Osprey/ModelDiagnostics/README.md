# Osprey `--model-diagnostics` runner scripts

Convenience wrappers for generating and validating the Osprey
`--model-diagnostics` HTML/PDF report. See the full workflow + the
`--protein-fdr` rationale in
`ai/docs/osprey-development-guide.md` -> "The `--model-diagnostics` report".

- **`Run-ModelDiagnostics.sh stellar|astral [pfdr]`** — clears the FDR-stage
  caches (keeps `*.scores.parquet`), re-runs Osprey with `--model-diagnostics`
  (+ `--fdrbench --fdrbench-pass 2` for the cross-check), then diffs the HTML
  pass-2 curve vs stock FDRBench via `../Compare/Compare-Fdrbench-Html.py`.
  As of pwiz #4395 the second pass is always on, so a plain run ALREADY
  populates the Model tab's 1st/2nd-pass selector and shows the shifted (~1.47%
  on Stellar libdecoy) pass-2 FDP — no `--protein-fdr` needed. Add `pfdr` to
  include `--protein-fdr 0.01` (into a separate `-pfdr` output dir); post-#4395
  that only sets the protein-q threshold (re-measure any residual effect on the
  reported ID count via #4390's q-clamp). Override the binary with
  `OSPREY_EXE=...`, data root with `OSPREY_TESTDIR=...`.

- **`Shot-ModelDiagnostics.py <html> <outdir> <stem>`** — headless-Chrome
  screenshots of the report's tabs/views (the browser extension can't
  screenshot `file://`); drives the tab/view/feature/pass clicks before
  capturing.

These replace the per-session bash scripts that lived under `ai/.tmp/`
(`reprocess-mdiag.sh`, `shot-mdiag.py`, `run-libtypes.sh`) — same pattern as
`Run-FdrBench.ps1` replacing the earlier `.tmp` FDRBench scripts.

Paths default to this machine's layout (primary `pwiz` checkout's net8.0
Release build; `D:/test/osprey-runs/{stellar,astral}-libdecoy`). Adapt them
for a different checkout/data root.
