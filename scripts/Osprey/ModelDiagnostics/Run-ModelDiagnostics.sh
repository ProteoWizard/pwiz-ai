#!/usr/bin/env bash
# Generate the Osprey --model-diagnostics HTML report for one dataset and
# cross-check its pass-2 FDR curve against stock FDRBench.
#
# It CLEARS the FDR-stage caches but KEEPS *.scores.parquet, so Osprey resumes
# from the (expensive) per-file scoring checkpoint and only re-runs the fast
# FDR / rescore / merge stages (~2 min Stellar). The report is emitted inside
# those stages -- there is no standalone "render the HTML from disk" path.
#
# Usage:  bash Run-ModelDiagnostics.sh stellar|astral [pfdr]
#   pfdr  -> add --protein-fdr 0.01 (see WHY below), into a separate -pfdr dir.
#
# WHY the pfdr toggle matters (read before choosing):
#   As of pwiz #4395 the SECOND Percolator retrain on the post-reconciliation
#   reported pool runs on ANY reconciled run, independent of --protein-fdr. So a
#   plain run ALREADY shows both report effects:
#     1) the Model tab's "1st pass / 2nd pass" selector is populated (two models);
#     2) the pass-2 FDR is shifted upward, because the retrain runs against a
#        decoy-DEPLETED null -- the known anti-conservative source
#        (project_osprey_pass2_recalibration_inflates_fdr). On Stellar libdecoy
#        the pass-2 combined FDP is ~1.47% vs the calibrated pass-1 ~0.90%.
#   Compare the two via the report's Pass 1 / Pass 2 selector in a single run.
#   pfdr now only sets the protein-q THRESHOLD (into a separate -pfdr dir);
#   re-measure any residual effect on the reported ID count (#4390's q-clamp).
#   Fix + kill-switch tracked in TODO-osprey_pass2_recalibration_fix.md.
#
# Override the binary with OSPREY_EXE=... (defaults to the primary pwiz checkout's
# net8.0 Release build). Data lives under $OSPREY_TESTDIR (default D:/test/osprey-runs).
set -uo pipefail
DS="${1:?usage: Run-ModelDiagnostics.sh stellar|astral [pfdr]}"
MODE="${2:-plain}"
EXE="${OSPREY_EXE:-C:/proj/pwiz/pwiz_tools/Osprey/Osprey/bin/x64/Release/net8.0/Osprey.exe}"
TESTDIR="${OSPREY_TESTDIR:-/d/test/osprey-runs}"
CMPTOOL="$(cd "$(dirname "${BASH_SOURCE[0]}")/../Compare" && pwd)/Compare-Fdrbench-Html.py"

case "$DS" in
  stellar) IN="$TESTDIR/stellar-libdecoy"; RES=unit; PFX=Ste ;;
  astral)  IN="$TESTDIR/astral-libdecoy";  RES=hram; PFX=Ast ;;
  *) echo "unknown dataset: $DS (expected stellar|astral)"; exit 2 ;;
esac
PROTEIN=(); SUFFIX=""
if [[ "$MODE" == "pfdr" ]]; then PROTEIN=(--protein-fdr 0.01); SUFFIX="-pfdr"; fi
OUT="$TESTDIR/_mdiag/${DS}${SUFFIX}"
STEM="$DS"
mkdir -p "$OUT"
mapfile -t MZML < <(ls "$IN/$PFX"-*.mzML)

echo "=== [$DS$SUFFIX] clearing FDR-stage caches (keeping *.scores.parquet + calibration) $(date) ==="
# FirstPassFDR must actually RETRAIN for the model table + per-feature histograms
# (a bundle-rehydrate resume omits them), so clear the 1st/2nd-pass sidecars too.
for pat in '*.1st-pass*' '*.2nd-pass*' '*.reconciliation*' '*.scores-reconciled*' \
           '*.blib*' '*.pairing.tsv' '*_fdp.csv' '*_fdrbench.tsv*' "$STEM.model-diagnostics."'*'; do
  find "$OUT" -maxdepth 1 -name "$pat" -print -delete 2>/dev/null
done

echo "=== [$DS$SUFFIX] running Osprey (--model-diagnostics${SUFFIX:+ --protein-fdr 0.01}) $(date) ==="
"$EXE" \
  -i "${MZML[@]}" \
  -l "$IN/carafe_spectral_library.tsv" -o "$OUT/$STEM.blib" \
  --resolution "$RES" --fdr-level precursor --threads 30 \
  --decoys-in-library --decoy-pairing-manifest "$IN/osprey_library_db_pairing.tsv" \
  --output-dir "$OUT" \
  --model-diagnostics \
  "${PROTEIN[@]}" \
  --fdrbench "$OUT/${STEM}_fdrbench.tsv" --fdrbench-pass 2 \
  > "$OUT/run-mdiag.log" 2>&1
echo "=== OSPREY EXIT=$? $(date) ==="; tail -20 "$OUT/run-mdiag.log"

echo "=== [$DS$SUFFIX] compare HTML pass-2 vs stock FDRBench $(date) ==="
python "$CMPTOOL" --dir "$OUT" --pass 2
echo "HTML: $OUT/$STEM.model-diagnostics.html"
