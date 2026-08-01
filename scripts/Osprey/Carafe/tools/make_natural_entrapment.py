#!/usr/bin/env python3
"""
Replace the shuffle-based entrapment (p_target / p_decoy) in an Osprey entrapment
library with MATCHED foreign-species (e.g. Arabidopsis) peptides. Targets and decoys
are kept byte-identical; only the two entrapment sequences per quartet change, so the
only experimental variable is the entrapment source.

Matching (the DIA-correct control): each human target is paired 1:1 with a unique
foreign peptide of matched neutral mass (co-locates in the same isolation window at
charges 2-3) and, in strict mode, matched length. Absence-filtered (no foreign peptide
equal to a human target). Deterministic. Uncovered targets fall back to a C-term-
preserving shuffle, and the fallback count is reported.

Usage:
  python make_natural_entrapment.py --method strict  --foreign <arab.fasta> --workdir <dir>
  python make_natural_entrapment.py --method relaxed --foreign <arab.fasta> --workdir <dir>
"""
import argparse, os, sys, random, bisect, zlib
from collections import defaultdict

MONO = {'G':57.02146,'A':71.03711,'S':87.03203,'P':97.05276,'V':99.06841,'T':101.04768,
 'C':103.00919,'L':113.08406,'I':113.08406,'N':114.04293,'D':115.02694,'Q':128.05858,
 'K':128.09496,'E':129.04259,'M':131.04049,'H':137.05891,'F':147.06841,'R':156.10111,
 'Y':163.06333,'W':186.07931}
AA = set(MONO)
H2O = 18.010565
CAM = 57.021464  # fixed carbamidomethyl on C

def pep_mass(seq):
    m = H2O
    for a in seq:
        r = MONO.get(a)
        if r is None: return None
        m += r + (CAM if a == 'C' else 0.0)
    return m

def digest(seq, max_mc=1, min_len=7, max_len=35):
    seq = seq.upper()
    cuts = [0] + [i+1 for i,a in enumerate(seq) if a in 'KR']
    if cuts[-1] != len(seq): cuts.append(len(seq))
    out = set()
    for i in range(len(cuts)-1):
        for mc in range(max_mc+1):
            j = i+mc+1
            if j >= len(cuts): break
            p = seq[cuts[i]:cuts[j]]
            if min_len <= len(p) <= max_len and set(p) <= AA:
                out.add(p)
    return out

def rev_cterm(s):  return s if len(s)<=2 else s[-2::-1]+s[-1]
def cyc_cterm(s,c):
    if len(s)<=2 or c==0: return s
    mid=s[:-1]; c%=len(mid); return mid[c:]+mid[:c]+s[-1]
def make_decoy(s, avoid):
    r=rev_cterm(s)
    if r!=s and r not in avoid: return r
    for c in range(1, min(len(s),10)+1):
        cc=cyc_cterm(s,c)
        if cc!=s and cc not in avoid: return cc
    return None
def shuffle_cterm(s, seed):
    if len(s)<=2: return s
    body=list(s[:-1]); rng=random.Random(seed)
    for i in range(len(body)-1,0,-1):
        j=rng.randint(0,i); body[i],body[j]=body[j],body[i]
    return ''.join(body)+s[-1]

def read_fasta(path):
    ents=[]; h=None; s=[]
    with open(path) as f:
        for ln in f:
            ln=ln.rstrip('\n')
            if ln.startswith('>'):
                if h is not None: ents.append([h,''.join(s)])
                h=ln[1:]; s=[]
            else: s.append(ln)
    if h is not None: ents.append([h,''.join(s)])
    return ents

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument('--method', choices=['strict','relaxed'], required=True)
    ap.add_argument('--foreign', required=True, help='foreign-species proteome FASTA')
    ap.add_argument('--workdir', required=True)
    ap.add_argument('--mass-tol', type=float, default=1.0, help='strict: |Δneutral mass| Da')
    ap.add_argument('--ratio', type=float, default=1.0,
                    help='fraction of targets that get a natural entrapment (unique-peptide r); '
                         'the rest are target+decoy only. 1.0 = one per target.')
    ap.add_argument('--seed', type=int, default=2024)
    a=ap.parse_args()

    man = os.path.join(a.workdir,'osprey_library_db_pairing.tsv')
    fas = os.path.join(a.workdir,'osprey_library_db_peptides.fasta')
    # Back up the shuffle originals once.
    for p in (man,fas):
        b=p+'.shuffle.bak'
        if not os.path.exists(b):
            import shutil; shutil.copy2(p,b)

    # --- read the (shuffle) manifest, group by pair_index: target,p_target,decoy,p_decoy ---
    rows=[]
    with open(man) as f:
        header=f.readline().rstrip('\n')
        for ln in f:
            rows.append(ln.rstrip('\n').split('\t'))
    groups=defaultdict(dict)   # pair_index -> {type: rowidx}
    for i,r in enumerate(rows):
        groups[r[4]][r[3]]=i
    order=sorted(groups, key=lambda k:int(k))
    targets=[rows[groups[k]['target']][0] for k in order]
    human_target_set=set(targets)
    print(f"targets: {len(targets)}", flush=True)

    # --- digest foreign proteome -> candidate pool, absence-filtered, indexed by length ---
    by_len=defaultdict(list)   # len -> sorted list of (mass, seq)
    seen=set()
    nprot=0
    for h,seq in read_fasta(a.foreign):
        nprot+=1
        for p in digest(seq):
            if p in seen or p in human_target_set: continue
            m=pep_mass(p)
            if m is None: continue
            seen.add(p); by_len[len(p)].append((m,p))
    for L in by_len: by_len[L].sort()
    ncand=sum(len(v) for v in by_len.values())
    print(f"foreign: {nprot} proteins -> {ncand} unique candidate peptides "
          f"(absence-filtered vs {len(human_target_set)} human targets)", flush=True)

    used=set()
    # index of mass-only list for relaxed cross-length fallback
    all_sorted=None

    def take_strict(mass,length):
        lst=by_len.get(length)
        if not lst: return None
        lo=bisect.bisect_left(lst,(mass-a.mass_tol,''))
        hi=bisect.bisect_right(lst,(mass+a.mass_tol,chr(0x10FFFF)))
        best=None;bestd=1e9
        for k in range(lo,hi):
            m,p=lst[k]
            if p in used: continue
            d=abs(m-mass)
            if d<bestd: bestd=d;best=p
        return best
    def take_relaxed(mass,length):
        # same length, nearest unused mass (any tol); else nearest length with a candidate
        for L in [length]+sorted(by_len, key=lambda x:abs(x-length)):
            lst=by_len.get(L)
            if not lst: continue
            lo=bisect.bisect_left(lst,(mass,''))
            # expand outward for nearest unused
            i,j=lo-1,lo; best=None;bestd=1e9
            while i>=0 or j<len(lst):
                for k in (i,j):
                    if 0<=k<len(lst):
                        m,p=lst[k]
                        if p not in used:
                            d=abs(m-mass)
                            if d<bestd: bestd=d;best=p
                if best is not None: break
                i-=1;j+=1
            if best is not None: return best
        return None

    # --- match every target, build new p_target / p_decoy ---
    stats={'natural':0,'fallback_shuffle':0}
    massdiffs=[]
    new_pt={}; new_pd={}
    for k in order:
        ti=groups[k]['target']; tseq=rows[ti][0]
        M=pep_mass(tseq); L=len(tseq)
        cand = take_strict(M,L) if a.method=='strict' else take_relaxed(M,L)
        if cand is None:
            pt=shuffle_cterm(tseq, a.seed ^ zlib.crc32(tseq.encode()))
            stats['fallback_shuffle']+=1
        else:
            used.add(cand); pt=cand; stats['natural']+=1
            massdiffs.append(abs(pep_mass(cand)-M))
        pd=make_decoy(pt, human_target_set) or rev_cterm(pt)
        new_pt[k]=pt; new_pd[k]=pd

    # --- select which quartets carry an entrapment (unique-peptide ratio r) ---
    selected=set(order)
    if a.ratio < 1.0:
        rng=random.Random(a.seed); shuf=list(order); rng.shuffle(shuf)
        selected=set(shuf[:round(a.ratio*len(order))])
    r_actual=len(selected)/len(order)

    # --- rewrite manifest: target+decoy always; p_target/p_decoy only if selected ---
    with open(man,'w',newline='') as f:
        f.write(header+'\n')
        for k in order:
            g=groups[k]
            f.write('\t'.join(rows[g['target']])+'\n')
            if k in selected:
                rpt=rows[g['p_target']][:]; rpt[0]=new_pt[k]; f.write('\t'.join(rpt)+'\n')
            f.write('\t'.join(rows[g['decoy']])+'\n')
            if k in selected:
                rpd=rows[g['p_decoy']][:]; rpd[0]=new_pd[k]; f.write('\t'.join(rpd)+'\n')

    # --- rewrite FASTA (entries per quartet: target,p_target,decoy,p_decoy) ---
    ents=read_fasta(fas)
    assert len(ents)==4*len(order), f"FASTA entries {len(ents)} != 4*{len(order)}"
    with open(fas,'w') as f:
        for qi,k in enumerate(order):
            base=4*qi
            if ents[base][1]!=rows[groups[k]['target']][0]:
                sys.exit(f"align mismatch at quartet {qi}")
            f.write('>'+ents[base][0]+'\n'+ents[base][1]+'\n')          # target
            if k in selected:
                f.write('>'+ents[base+1][0]+'\n'+new_pt[k]+'\n')        # p_target
            f.write('>'+ents[base+2][0]+'\n'+ents[base+2][1]+'\n')      # decoy
            if k in selected:
                f.write('>'+ents[base+3][0]+'\n'+new_pd[k]+'\n')        # p_decoy
    print(f"entrapment ratio r = {r_actual:.4f} ({len(selected)}/{len(order)} targets carry entrapment)", flush=True)

    md=sorted(massdiffs)
    med=md[len(md)//2] if md else 0.0
    print(f"[{a.method}] natural={stats['natural']} "
          f"shuffle_fallback={stats['fallback_shuffle']} "
          f"coverage={100*stats['natural']/len(order):.1f}%  "
          f"median_abs_dmass={med:.3f}Da  max_abs_dmass={md[-1] if md else 0:.2f}Da", flush=True)
    print(f"wrote {man}\nwrote {fas}", flush=True)

if __name__=='__main__':
    main()
