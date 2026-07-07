# TODO: Foreign-source (nr/Arabidopsis) decoys+entrapment — MS1 power WITHOUT biasing FDP

**Status**: Backlog (brendanx67). Research sprint, **ready for a `/night-session`** (needs ~90%
context + ~7 h). Created 2026-07-07 from a long research session; this file is self-contained so a
fresh session can run it cold. **Requested by**: Brendan.

## The question (one sentence)
Can we draw decoys **and** entrapment peptides from a real foreign proteome (nr, or Arabidopsis as
the tractable stand-in) so the FDR model gains **MS1 discriminative power** (better detection) while
its q-values stay **honest** (accurate FDP), instead of the isobaric-reverse decoy that is honest but
MS1-blind? Concretely: is there a decoy that is BOTH equal-chance-valid AND MS1-informative — and does
using a single large natural pool (nr) for both decoys and entrapment achieve it without a *masked*
bias where the two agree with each other but both undercount the true human FDP?

## Why this matters
On HRAM DIA, MS1 precursor features (co-elution, isotope dot-product) carry real information for
separating correct from incorrect IDs, but Osprey's **isobaric reverse decoys drive MS1 weight to ~0**
(measured: +0.16%). Recovering that MS1 power honestly could add ~10% sensitivity at a fixed true FDR.
This is the sensitivity side of the same axis as the partial-entrapment PR #4380 (the calibration
side). Ties to [[project_osprey_natural_entrapment]], [[TODO-osprey_assumption_failure_detection]]
(the diagnostics that would detect a bad decoy), and PR #4380 / `fractional-entrapment.md`.

---

## WHAT IS ALREADY ESTABLISHED (do NOT re-run these — read, then build on)
Full write-up: **`ai/.tmp/night-report-decoy-mz-collision.md`** (§1–§7). Lit review:
`ai/.tmp/night-lit-report.md`. All numbers below are Astral HRAM, pass-1 experiment scope,
`--model-diagnostics`, no `--protein-fdr`, isobaric entrapment as the true-FDP oracle.

1. **Isobaric reverse decoys suppress MS1** (weight +0.16% ≈ 0), give honest FDP (1.92% @ reported
   1% q), 71,243 IDs @ true FDP=1%.
2. **Every m/z manipulation of the reverse decoy is anti-conservative** — none gives honest MS1 power:
   | decoy | MS1 wt | FDP@1%q | IDs@true-1% |
   |---|---|---|---|
   | isobaric (baseline) | 0.16% | 1.92% (honest) | 71,243 |
   | +0.5 Th (charge-3 → mass-defect no-man's-land artifact) | 3.71% | 2.06% | 74,179 |
   | +10 Th (Skyline default; defect-correct) | 3.25% | 3.05% | 80,001 |
   | charge-permute (real occupied same-charge m/z) | 3.59% | 4.35% | 78,635 |
   | charge-blind permute (impossible masses) | 1.76% | 3.99% | 68,405 |
3. **THE REFRAME**: the reverse decoy's MS1-blindness is the **anagram** (same fragment masses as its
   target → it co-locates on the target's chromatographic peak → the target's precursor co-elutes →
   decoy looks target-like on MS1 → weight → 0). It is NOT the isobaric m/z per se. So the lever is the
   *fragments*, not the m/z.
4. **CRITICAL — the proxies can't answer this.** All five experiments above kept **incoherent,
   reversed-target (anagram) fragments** (mass-M1 fragments stapled to a precursor claiming mass M2). A
   real foreign peptide is **coherent** (fragments sum to its own precursor) and **non-anagram**. So
   none of the proxies predict real-foreign-decoy behavior — the charge-permute 4.35% is most likely an
   incoherence artifact, not a verdict on foreign decoys. **This experiment needs REAL foreign spectra.**
5. **m/z-occupancy (`ai/.tmp/occupancy_test.py`)**: the human precursor m/z space is SATURATED — **93.9%
   of Arabidopsis peptides fall within 2 ppm of a human target m/z** (charge 3: 90.5%; median 0.0 ppm;
   810k charge-2 targets ≈ 0.8 precursors/ppm on the mass-defect line). So foreign peptides at NATIVE
   m/z sit at **occupied** m/z (a real human precursor within tolerance) → MS1-representative of a real
   false target. **Collision-avoidance (`--min-target-sep-ppm`) is COUNTERPRODUCTIVE** — only ~6% of
   foreign peptides are in gaps, and those are the non-representative ones. **Use native m/z** (Brendan's
   2008 nr approach). This reversed an earlier (wrong) "avoid collisions" conclusion.
6. **Literature (all corroborate the framework)** — read `ai/.tmp/night-lit-report.md`,
   `ai/.tmp/poster_bernhardt.txt`, `ai/.tmp/biorxiv2026.txt`:
   - **Bernhardt/Bruderer (Biognosys) 2016** poster: on HRAM, used *E. coli* as a ground-truth negative
     control; scrambled/inverted (isobaric) decoys are accurate/conservative, a fragment-m/z-shift decoy
     underestimates FDR (2.3% true @ 1% est) with the most IDs (a mirage). "IDs alone are not a
     qualifier." = our result, 9 yr early.
   - **diagFDR — Chion et al., bioRxiv Apr 2026**: formalizes the **"equal-chance"** assumption; the
     **granularity paradox** (sharper separation → sparse decoy tail → fragile FDR, worse on HRAM);
     interpret **FDPentrap comparatively** (≫α = anti-conservative; ≈α is NOT proof — an optimistic
     decoy + pessimistic entrapment can cancel; this is our "collusion/shift-both trap"). Three
     entrapment-proteome criteria (absent / large enough / phylogenetically distant) validate nr.
   - **Chan, Madej, Chung, Lam (JPR 2025)**: template decoys in *predicted* libraries (our Carafe
     setting) systematically violate equal-chance. Also: Wen 2025 [entrapment]; Couté 2020 [granularity];
     Freestone/Noble/Keich 2024 [Percolator cross-run]; TargetDecoy pkg (Debrie 2023).

**Bottom line going in**: the outcome for real foreign decoys is genuinely OPEN and looks promising —
the one first-principles reason it would fail on HRAM (empty m/z) was ruled out by finding (5).

---

## THE EXPERIMENT TO RUN

### Recommended path: minimal first, then the symmetric nr-for-both
Do (A) first — it answers the load-bearing question with ONE entrapment set (no dual-oracle tooling);
only do (B) if (A) is promising.

**(A) MINIMAL — foreign decoys + isobaric-human oracle.** Library = human targets + **Arabidopsis
decoys** (real Carafe spectra, native m/z, homology-filtered, distribution-matched, labeled decoy) +
**isobaric-human-shuffle entrapment** (the existing representative oracle). Run Osprey; read MS1 feature
weights + FDPentrap from the human oracle.
- Success = **MS1 total weight rises well above baseline's 0.16% AND FDPentrap stays ≈ 1% (not ≫1%)**
  under the human oracle, with IDs@true-FDP=1% > baseline 71,243. That is a decoy that is honest AND
  MS1-powerful — the goal.
- Failure modes: MS1 rises but FDPentrap ≫ 1% (anti-conservative, like the shifts) → foreign decoys are
  also non-representative → the anagram wasn't the only issue; OR MS1 stays ~0 → foreign decoys
  co-locate too (unlikely, they're non-anagram).

**(B) FULL nr-for-both.** Add a second, disjoint **Arabidopsis entrapment** set alongside the human
oracle. Question: does the Arabidopsis-entrapment FDP agree with the Arabidopsis-decoy q-value (self-
consistent) AND with the independent human oracle (honest)? If Arabidopsis-entrap ≈ q but the human
oracle reads higher → nr-for-both is self-consistent but **masks** bias (the diagFDR "cancel" warning).
Needs Osprey to report FDP for TWO entrapment classes (dual-label the pairing manifest and split
accepted entrapment by source, or run twice) — **the non-trivial tooling; scope it before building.**

### Phases
1. **Peptide selection (CPU, ~10 min).** Digest Arabidopsis
   (`D:/test/entrapment/arabidopsis/UP000006548.fasta`), homology-filter against the human target set,
   mass-match to human targets (co-locate in the same isolation window; native m/z — do NOT shift, do
   NOT collision-avoid), draw disjoint 1:1 sets: decoy set A (for A/B) and entrapment set B (for B).
   Reuse/adapt `ai/.tmp/make_natural_entrapment.py` (it already digests + homology-filters + mass-matches
   Arabidopsis; extend to emit two disjoint sets + a decoy set). Distribution-match on length + charge +
   precursor-mass so the only intended difference from targets is "not really present."
2. **Carafe spectral prediction + library assembly (GPU, ~1–2 h).** Predict fragment intensities + RT
   for the Arabidopsis peptides (peptdeep) and assemble the search library with the foreign peptides as
   decoys (and, for B, as a second entrapment). Use the Carafe workflow — see
   [[project_osprey_carafe_library_selfsufficiency]] and the recipe at
   `ai/.tmp/osprey-library-generation-recipe.md`; orchestrator `ai/.tmp/Run-CarafeOspreyWorkflow.ps1`;
   `maccoss/Carafe` → `C:\proj\Carafe-mm`. The pairing manifest must label targets / foreign-decoys /
   entrapment correctly for `--decoys-in-library --decoy-pairing-manifest`.
3. **Osprey run + extract (async).** Run on the 3 Astral mzML at `--threads 8` (see gotchas), then
   `python ai/.tmp/extract_mdiag.py <out>/astral.model-diagnostics.html` for MS1 weights + FDP, and the
   inline true-FDP snippet (below) for IDs@true-FDP=1%.
4. **Analysis + write-up.** Fill the (A) success table; compare to the baselines. Append results to
   `ai/.tmp/night-report-decoy-mz-collision.md` (new §), update [[project_osprey_natural_entrapment]].

---

## STARTUP PROTOCOL (for the night session)
1. Load skills: **osprey-development**, and **version-control** if committing. Read this file, then
   `ai/.tmp/night-report-decoy-mz-collision.md` (the full context) and `ai/.tmp/occupancy_test.py`.
2. `mcp__status__get_project_status()`. Active pwiz checkout: `C:\proj\pwiz`.
3. Osprey build (if needed): `pwsh -File ./ai/scripts/Osprey/Build-Osprey.ps1 -Configuration Release
   -TargetFramework net8.0 -SourceRoot C:/proj/pwiz`. Exe:
   `C:/proj/pwiz/pwiz_tools/Osprey/Osprey/bin/x64/Release/net8.0/Osprey.exe`.
4. Osprey run pattern (proven tonight; **always `--threads 8` on Astral**):
   ```
   <Osprey.exe> \
     -i D:/test/osprey-runs/astral-libdecoy/Ast-2024-12-05_HeLa_3mzDIA_6mIIT_400-900_{49,55,60}.mzML \
     -l <NEW library.tsv> -o <OUT>/astral.blib \
     --resolution hram --fdr-level precursor --threads 8 \
     --decoys-in-library --decoy-pairing-manifest <NEW pairing.tsv> \
     --output-dir <OUT> --model-diagnostics
   ```
5. **Launch Osprey DETACHED** so it survives (see gotcha): write a `run_X.ps1` (see
   `ai/.tmp/run_permz.ps1` as a template) and `Start-Process pwsh -ArgumentList '-NoProfile','-File',
   '<run_X.ps1>' -WindowStyle Hidden`. Then use **ScheduleWakeup** (~1300–1500 s) to collect; a run is
   ~20–26 min. Confirm done via `grep -c "Analysis complete" <OUT>/osprey-run.log`.

## KEY PATHS / TOOLING / DATA
- **Astral data + baseline library** (human target+decoy+entrapment, 13 GB):
  `D:/test/osprey-runs/astral-libdecoy/` — `carafe_spectral_library.tsv`,
  `osprey_library_db_pairing.tsv`, 3× `Ast-*.mzML`. Baseline report already computed:
  `D:/test/osprey-runs/_mdiag/astral/astral.model-diagnostics.html`.
- **Arabidopsis FASTA**: `D:/test/entrapment/arabidopsis/UP000006548.fasta` (39k prot).
- **Scripts (all in `ai/.tmp/`)**: `make_natural_entrapment.py` (digest+homology+mass-match — the base
  for Phase 1), `occupancy_test.py` (the saturation measurement), `extract_mdiag.py` (MS1 weights +
  FDP@q from the report JSON), `shift_decoy_mz.py` / `permute_decoy_mz*.py` (proxy generators — NOT for
  this experiment, keep anagram fragments), `mass_defect_analysis.py`, `mem-sampler.ps1`,
  `job-probe.ps1`, `run_permz.ps1` (detached-launch template), `Run-CarafeOspreyWorkflow.ps1`.
- **Reports/PDFs**: `night-report-decoy-mz-collision.md`, `night-lit-report.md`,
  `poster_bernhardt.txt` (Biognosys 2016), `biorxiv2026.txt` (diagFDR), `s41592-025-02719-x.pdf` (Wen).
- **PDF reading**: `pypdf` is installed; `python -c "from pypdf import PdfReader; ..."` (console is
  cp1252 — write text to a file with `encoding='utf-8'` and Read it, don't print Unicode to stdout).

### Inline true-FDP=1% snippet (IDs at a matched honest threshold)
```
python - <<'EOF'
import re,json
def load(p):
    h=open(p,encoding="utf-8").read()
    return json.loads(re.search(r'<script[^>]*id="osprey-data"[^>]*>(.*?)</script>',h,re.S).group(1))
def dt(v,t=0.01):
    c=v["combined"];nt=v["nTargetAccepted"];b=None
    for i in range(len(c)):
        if c[i]<=t: b=i
    return (nt[b],c[b]*100) if b is not None else (0,None)
D=load("<OUT>/astral.model-diagnostics.html")
for v in D["fdpViews"]:
    if v["scope"]=="experiment" and v["pass"]==1:
        print("IDs@true-FDP=1% =", dt(v))
EOF
```

## GOTCHAS (all learned the hard way tonight)
- **`--threads 8` on Astral, never 30.** `--threads 30` drives pass-2 to ~98 GB committed and gets a
  SILENT OOM kill (the Bash Job Object has `DIE_ON_UNHANDLED_EXCEPTION`, suppressing WER). ≤12 has
  margin; 8 is proven. See [[reference_osprey_astral_thread_memory_oom]].
- **Background Bash tasks get killed unpredictably** (waiters, Osprey wrappers). Osprey SURVIVES when
  launched **detached via `Start-Process`** (it breaks away from the job). Do NOT rely on a background
  `bash` waiter for a long run — use ScheduleWakeup to re-collect, and poll with foreground commands.
- A full fresh Astral score (new library, no cache) is ~20–26 min. Building a shifted 13 GB library
  streams in ~3–10 min; disk `D:` has ~9.8 TB free.
- The decoy-pairing manifest pairs by **sequence**, so foreign decoys need pairing handled (reverse
  decoys are born paired; foreign are not — relax/assign, see [[TODO-osprey_assumption_failure_detection]]
  note; pairing is needed for the paired estimator, NOT for basic Percolator FDR).
- Homology-filter foreign peptides against ALL human target sequences (a foreign peptide equal to a
  human target would be a real ID, not a decoy). Many Arabidopsis tryptic peptides are mass-collisions
  (not sequence matches) with human — that is fine and expected (finding 5).

## BASELINES TO BEAT / COMPARE (Astral HRAM, pass-1 exp scope)
- Isobaric reverse decoys (current Osprey): **MS1 total +0.16%**, FDP@1%q **1.92%**, **71,243** IDs @
  true-FDP=1%. Report: `D:/test/osprey-runs/_mdiag/astral/astral.model-diagnostics.html`.
- Target of this experiment: MS1 total ≫ 0.16% **and** FDPentrap ≈ 1% (human oracle) **and**
  IDs@true-FDP=1% > 71,243.

## Success criterion (in diagFDR language)
A decoy that **raises MS1 feature weight while keeping the equal-chance / null-alignment diagnostic
flat and FDPentrap ≈ α under an independent isobaric-human oracle.** If real foreign decoys achieve
this, it is a genuinely new, publishable result (nobody has shown an MS1-honest non-isobaric decoy);
if not, it strengthens "MS1 power requires the external isobaric oracle" (the PR #4380 recipe).

## Related
- [[project_osprey_natural_entrapment]] (all night's findings + tooling), PR #4380 +
  `pwiz_tools/Osprey/docs/fractional-entrapment.md` (the calibration side / oracle),
  [[TODO-osprey_assumption_failure_detection]] (equal-chance diagnostics that would grade a decoy),
  [[project_osprey_carafe_library_selfsufficiency]] (how to run the Carafe build),
  [[reference_osprey_astral_thread_memory_oom]] (the --threads gotcha).
