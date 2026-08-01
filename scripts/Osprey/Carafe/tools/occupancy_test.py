#!/usr/bin/env python3
"""How often does a foreign (Arabidopsis) peptide's precursor m/z land on a real HUMAN precursor?
This decides whether foreign decoys/entrapment sit at OCCUPIED m/z (MS1-representative of a real
false target -> honest) or EMPTY ppm-space (MS1-penalized -> masked-bias trap) on HRAM.

For a sample of tryptic Arabidopsis peptides (charge 2 and 3), compute the min ppm distance to the
nearest human TARGET precursor m/z of the same charge (from the Astral libdecoy library).
"""
import sys, bisect

PROTON = 1.007276
WATER = 18.010565
# monoisotopic residue masses; Cys carbamidomethylated (+57.02146), matching the target library
AA = {'G':57.02146,'A':71.03711,'S':87.03203,'P':97.05276,'V':99.06841,'T':101.04768,
      'C':160.03065,'L':113.08406,'I':113.08406,'N':114.04293,'D':115.02694,'Q':128.05858,
      'K':128.09496,'E':129.04259,'M':131.04049,'H':137.05891,'F':147.06841,'R':156.10111,
      'Y':163.06333,'W':186.07931}
LIB = "D:/test/osprey-runs/astral-libdecoy/carafe_spectral_library.tsv"
FASTA = "D:/test/entrapment/arabidopsis/UP000006548.fasta"
PREC, CHG, PROT = 2, 3, 5

# --- human target precursor m/z per charge (dedup by modpep+charge) ---
sys.stderr.write("reading human target m/z...\n")
human = {2: [], 3: []}
seen = set()
with open(LIB, "r", encoding="utf-8") as f:
    f.readline()
    for line in f:
        p = line.split("\t")
        prot = p[PROT]
        if prot.startswith(("decoy_","DECOY_","rev_")) or ("_p_target" in prot):
            continue  # pure human targets only
        key = (p[0], p[CHG])
        if key in seen: continue
        seen.add(key)
        try:
            z = int(p[CHG]); mz = float(p[PREC])
        except ValueError:
            continue
        if z in human: human[z].append(mz)
for z in human: human[z].sort()
sys.stderr.write("human targets: z2=%d z3=%d\n" % (len(human[2]), len(human[3])))

def pep_mass(seq):
    m = WATER
    for a in seq:
        if a not in AA: return None
        m += AA[a]
    return m

def digest(seq):
    peps, start = [], 0
    for i, a in enumerate(seq):
        if a in "KR" and not (i+1 < len(seq) and seq[i+1] == 'P'):
            peps.append(seq[start:i+1]); start = i+1
    if start < len(seq): peps.append(seq[start:])
    # 0 and 1 missed cleavage
    out = list(peps)
    for i in range(len(peps)-1):
        out.append(peps[i] + peps[i+1])
    return out

def nearest_ppm(mz, arr):
    i = bisect.bisect_left(arr, mz)
    best = 1e9
    for j in (i-1, i):
        if 0 <= j < len(arr):
            d = abs(arr[j] - mz) / mz * 1e6
            if d < best: best = d
    return best

# --- digest Arabidopsis, sample peptides ---
sys.stderr.write("digesting Arabidopsis...\n")
pep_set = set()
seq = ""
def flush(s):
    if not s: return
    for pep in digest(s):
        if 7 <= len(pep) <= 30:
            pep_set.add(pep)
with open(FASTA, "r", encoding="utf-8") as f:
    for line in f:
        if line.startswith(">"):
            flush(seq); seq = ""
        else:
            seq += line.strip()
flush(seq)
# drop peptides that are also human targets? keep — exact matches are legit 0-ppm coincidences
sys.stderr.write("Arabidopsis unique peptides (len7-30): %d\n" % len(pep_set))

# --- occupancy ---
BINS = [2, 5, 10, 20, 50, 100]
for z in (2, 3):
    arr = human[z]
    counts = {b: 0 for b in BINS}
    n = 0; ppms = []
    for pep in pep_set:
        m = pep_mass(pep)
        if m is None: continue
        mz = (m + z * PROTON) / z
        if mz < 380 or mz > 920:  # outside the 400-900 acquisition (with margin)
            continue
        d = nearest_ppm(mz, arr)
        ppms.append(d); n += 1
        for b in BINS:
            if d <= b: counts[b] += 1
    ppms.sort()
    med = ppms[len(ppms)//2] if ppms else float('nan')
    print(f"charge {z}: n={n} Arabidopsis precursors in range; median nearest-human = {med:.1f} ppm")
    for b in BINS:
        print(f"    within {b:3d} ppm of a human target: {counts[b]:7d}  ({100.0*counts[b]/max(1,n):.1f}%)")
