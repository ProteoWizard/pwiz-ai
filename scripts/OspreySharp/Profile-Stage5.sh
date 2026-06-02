#!/usr/bin/env bash
# One-shot Stellar single-file Stage 5 profile for both impls.
# Phases:
#   1. Freeze Rust Stage 1-4 in /home (C# freeze already done)
#   2. Profile C# Stage 5 under dottrace (sampling)
#   3. Profile Rust Stage 5 under samply
set -e

BASE=/home/brendanx/test/osprey-runs/stellar/_test_snapshot_profile-prep
CSDIR=$BASE/stage1to4/cs
RUSTDIR=$BASE/stage1to4/rust
OUT=/home/brendanx/test/osprey-runs/stellar/_profile_stage5
mkdir -p "$OUT"

OSPREY_SHARP=/mnt/c/proj/pwiz/pwiz_tools/OspreySharp/OspreySharp/bin/x64/Release/net8.0/OspreySharp
OSPREY_RUST=/mnt/c/proj/osprey/target/release/osprey
DOTTRACE=/home/brendanx/.dotnet/tools/dottrace
SAMPLY=/home/brendanx/.cargo/bin/samply

INPUTS=/home/brendanx/test/osprey-runs/stellar
MZML_NAME=$(ls "$INPUTS"/Ste-*.mzML | head -1 | xargs -n1 basename)
LIB_NAME=$(ls "$INPUTS"/*.tsv | head -1 | xargs -n1 basename)
SCORES_NAME=${MZML_NAME%.mzML}.scores.parquet

echo "MZML=$MZML_NAME  LIB=$LIB_NAME  SCORES=$SCORES_NAME"
echo ""

# ---- Phase 1: Rust Stage 1-4 freeze (C# was done by Test-Snapshot) ----
if [ ! -f "$RUSTDIR/$SCORES_NAME" ]; then
    echo "=== Rust Stage 1-4 freeze ==="
    mkdir -p "$RUSTDIR"
    cp "$INPUTS/$MZML_NAME" "$INPUTS/$LIB_NAME" "$INPUTS/${LIB_NAME}.libcache" "$RUSTDIR/" 2>/dev/null || true
    cd "$RUSTDIR"
    time "$OSPREY_RUST" \
        -i "$MZML_NAME" -l "$LIB_NAME" -o /tmp/_freeze_rust.blib \
        --resolution unit --threads 16 --no-join 2>&1 | tail -10
    echo ""
fi

# ---- Phase 2: C# Stage 5 under dottrace ----
echo "=== C# Stage 5 under dottrace (sampling) ==="
cd "$CSDIR"
export OSPREY_PERCOLATOR_ONLY=1
CS_DTP=$OUT/csharp-stage5-stellar.dtp
rm -f "$CS_DTP"
time "$DOTTRACE" start \
    --framework=NetCore \
    --profiling-type=Sampling \
    --save-to="$CS_DTP" \
    --propagate-exit-code \
    --overwrite \
    "$OSPREY_SHARP" \
    -- \
    -l "$LIB_NAME" -o /tmp/_prof_cs.blib \
    --resolution unit --threads 16 \
    --join-at-pass=1 --input-scores "$SCORES_NAME" 2>&1 | tail -15
echo ""
ls -la "$CS_DTP"
echo ""

# ---- Phase 3: Rust Stage 5 under samply ----
echo "=== Rust Stage 5 under samply ==="
cd "$RUSTDIR"
RUST_JSON=$OUT/rust-stage5-stellar.json
rm -f "$RUST_JSON"
time "$SAMPLY" record --save-only --no-open -o "$RUST_JSON" \
    -- \
    "$OSPREY_RUST" \
    -l "$LIB_NAME" -o /tmp/_prof_rust.blib \
    --resolution unit --threads 16 \
    --join-at-pass=1 --input-scores "$SCORES_NAME" 2>&1 | tail -15
echo ""
ls -la "$RUST_JSON"
echo ""

unset OSPREY_PERCOLATOR_ONLY
echo "=== Profiles ==="
echo "  C#:   $CS_DTP"
echo "  Rust: $RUST_JSON"
