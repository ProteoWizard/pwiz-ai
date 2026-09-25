# Osprey Demultiplexing: Design Specification

**Status:** draft for discussion
**Scope:** overlapping-window demultiplexing inside Osprey for staggered Orbitrap / Orbitrap Astral DIA, SCIEX ZT Scan DIA, and Waters SONAR
**Author:** MacCoss lab
**Date:** August 2026

---

## 1. Goals and non-goals

### Goals

1. One demultiplexing subsystem that handles every acquisition scheme where a precursor bin is sampled by more than one isolation event, whether those events are in adjacent cycles (stepped staggered) or adjacent scan positions within a cycle (scanning quadrupole).
2. Demultiplex once, at cache build time, and persist the result in `.spectra.bin` so the cost is never paid twice.
3. Recover interference-free fragment intensities, not just narrower nominal windows. The quantitative benefit is the point; identification gains are secondary.
4. Stay inside a 32 GB working set on a 60 minute Astral run or a 30 minute 858 Hz ZT Scan run, with room for the rest of the search.
5. Preserve Osprey's bitwise determinism guarantees under threading and SIMD.

### Non-goals

- Modifying msconvert to demultiplex. Osprey owns the demux.
- Demultiplexing MS1. MS1 records pass through untouched.
- Library-informed or targeted demux. The cache must remain a pure function of the raw file plus the demux parameter set, so it stays shareable across analyses.

---

## 2. Unified forward model

Every scheme in scope is the same linear problem. For a fixed fragment m/z channel at a fixed retention time:

```
y = A x + n,   x >= 0
```

- `y` (length M): observed intensity of that fragment channel in each of the M multiplexed isolation events that could contain it.
- `x` (length N): the unknown intensity contributed by each narrow precursor bin.
- `A` (M x N): the **accumulation-time-weighted transmission** of bin *j* into event *i* (Section 2.0), not simply a 0/1 membership indicator.
- `n`: measurement noise, with a scheme-dependent variance model (Section 6).

Everything that differs between Orbitrap staggering, ZT Scan, SONAR, and parallel isolation multiplexing is confined to three things: how `A` is built, how the M events are gathered in time, and what the noise model is. The solver is shared. Nothing in this formulation requires the isolated m/z range to be contiguous, which is what lets the same machinery cover comb-shaped parallel isolation (Section 2.5).

### 2.0 What the entries of `A` actually are

The natural first guess is that `A[i][j]` is 1 when event *i* isolates bin *j* and 0 otherwise. That is wrong in general, and the correct definition unifies every scheme in this document.

Reported intensity is a rate, `y = alpha * N / IT` (Section 6.2). The ions in event *i* are the sum over bins of each precursor's ion current times **the time that event spent accumulating that particular bin**:

```
N_i = sum over j of  current_j * tau_ij
```

where `tau_ij` is the accumulation time event *i* devoted to bin *j*. Writing `x_j = alpha * current_j`, which is the intensity a narrow-window measurement of bin *j* would report, gives

```
y_i = sum over j of  x_j * (tau_ij / IT_i)
```

so

```
A[i][j] = transmission(bin j, event i) * tau_ij / IT_i
```

**Why the 0/1 assumption has been invisible until now.** When every co-isolated bin receives the same fill time, `tau_ij = IT_i / k` for all included bins, so `A` is a constant `1/k` times a 0/1 matrix. A uniform scale factor rescales `x` and changes nothing relative, which is why implementations assuming equal injection times give correct answers on equal-fill data. The moment fill times differ between co-isolated precursors, the 0/1 matrix is simply the wrong operator and the solve is biased in a way no amount of solver quality recovers.

**This is the same quantity as the scanning-quadrupole kernel.** In ZT Scan and SONAR, `tau_ij` is the dwell time of the sweep over bin *j* during event *i*, convolved with the quadrupole transmission profile. The transfer function of Section 2.3 and the fill-time allocation of a multiplexed co-isolation are not analogous, they are identical: how much accumulation each precursor bin received in that event. Section 2.3 is the continuous case, MSX is the discrete case, and one implementation covers both.

**Consequences:**

- Read per-sub-window accumulation times where the vendor exposes them, and fall back to the equal-fill assumption only when they are genuinely unavailable. Record which was used in the metrics JSON, since it changes the interpretation of every downstream number.
- Add a determinability diagnostic: **cumulative accumulation time per bin across the group**, `sum over i of tau_ij`. A bin that received short fills in every event containing it is poorly determined regardless of how many events contain it, and overlap count alone will not reveal that.
- The noise weighting in Section 6.2 is unaffected. It depends on total counts in the event, so `w_i = IT_i / (alpha * y_i)` still holds.

### 2.1 Acquisition taxonomy

| | Stepped staggered (Orbitrap, Astral) | Scanning quadrupole (ZT Scan, SONAR) | Parallel isolation multiplexing (comb) |
|---|---|---|---|
| Overlap factor *k* | 2 (50%), 3 (33%), 4 (25%) | typically 4 to 7, set by bin width vs. sweep width | overlaps per unit per cycle, 2 or more by design |
| Where the redundant events live | Different cycles, *k* cycles apart | Adjacent scan positions in the **same** cycle | Different acquisitions within a cycle or sub-cycle |
| Time separation of the M events | One full cycle each, 0.5 to 3 s | Sub-cycle, order 1 to 20 ms | Part of a cycle, reduced further by sub-cycling |
| RT interpolation needed | **Yes**, mandatory | No | Yes, but over a shorter span |
| Shape of `A` rows | Near-boxcar, from declared window bounds | Smooth kernel: quad transmission convolved with sweep, plus collision-cell tail | Sparse 0/1 comb, or soft-edged comb if the isolation waveform is shaped |
| Where `A` comes from | Isolation window bounds in the file | Empirical calibration, optionally aided by sweep metadata | Sub-window bounds in the file, plus edge profile if non-square |
| Window geometry | Often variable width across the range | Uniform bin width, m/z-dependent kernel | Fixed unit width, comb pattern may vary with m/z or through the gradient |
| Locality of coupling | Local, *k* adjacent bins | Local, sweep width | **Non-local**, coupled units span the full comb |
| Conditioning | Rank-deficient by *k*-1 | Rank-deficient, kernel-dependent | **Can be made full rank by design** |

Two rows do the design work.

**Time separation.** In the scanning case the redundant measurements are essentially simultaneous, so the chromatographic peak has not moved between them and the linear system is clean. In the stepped case the M measurements are separated by whole cycles, and on a fast gradient the analyte intensity can change by tens of percent between them. That temporal skew, not the algebra, is the dominant error source for staggered Orbitrap data. Comb acquisition sits between the two, and the sub-cycle orderings in the parallel isolation scheme exist partly to shrink that gap.

**Locality and conditioning.** These are the two rows where comb acquisition genuinely differs rather than merely varying, and Section 2.5 deals with both. The short version is that giving up locality is what buys the conditioning, and the conditioning is worth more.

### 2.2 Design matrix, stepped staggered

Build `A` from the isolation window bounds actually present in the file. Do not assume a uniform ladder. Astral methods routinely use variable-width windows, and the staggered pair is generated by offsetting a variable schedule, so the resulting bin widths are not constant across the precursor range.

Procedure per demux group:

1. Collect the distinct isolation windows `[lo_i, hi_i]` participating in the group.
2. Form the sorted union of all boundaries. The intervals between consecutive boundaries are the narrow bins. For a clean *k*-fold stagger this reproduces bins of width W/*k*, but it degrades gracefully when the stagger is imperfect.
3. `A[i][j] = overlap(window_i, bin_j) / width(bin_j)`, which is 1 or 0 for exact boxcar transmission.
4. Optionally soften the edges: real quadrupole transmission rolls off over roughly 0.2 to 0.5 Th. Model each edge as a linear ramp of width `edgeWidth` and integrate. This is a single scalar parameter and it measurably reduces edge-bin artifacts.

Cache `A` keyed on the group geometry. There will be at most a few hundred distinct geometries per file, so the factorizations in Section 6 are computed a few hundred times, not tens of millions.

### 2.3 Transfer function, scanning quadrupole

Here `A` is not derivable from a declared window. The effective response of bin *j* to a precursor at m/z *m* is

```
A[i][j]  =  (T * S)(m - c_i)  convolved with  L
```

where `T` is the quadrupole transmission profile (approximately trapezoidal, width W, edge roll-off proportional to m/z), `S` is a rectangle of width equal to the m/z traversed during that bin's accumulation interval, and `L` is a causal smearing kernel from ion residence in the collision cell and Zeno trap. SCIEX explicitly does not empty the collision cell between windows in ZT Scan, so `L` is a one-sided exponential-like tail that shifts apparent precursor mass upward in the sweep direction. SONAR has the same structure with different constants.

**Do not assume a boxcar here.** Deconvolving with a rectangle when the true kernel is a lagged trapezoid produces systematic mass-direction bias and ringing that is worse than not demultiplexing at all.

### 2.4 Empirical kernel calibration

The kernel is measurable from the data itself, which de-risks the whole project: it does not depend on ProteoWizard exposing sweep geometry.

1. Find abundant, chromatographically resolved precursors. The surviving unfragmented precursor ion in the MS2 spectra is the cleanest probe, since its m/z equals the precursor m/z exactly and it appears in every bin that transmits it.
2. At the chromatographic apex, extract intensity versus bin index. That trace **is** the transfer function sampled at that m/z, up to a scale factor.
3. Normalize, and fit a parametric model: trapezoid width, edge roll-off, lag, tail time constant. Four to five parameters.
4. Fit each parameter as a smooth low-order function of m/z across the precursor range, using a few hundred probes. Store the coefficients.
5. Regenerate `A` per group from the fitted model.

If and when pwiz exposes per-bin sweep start and stop, use it to initialize the fit and to validate the recovered lag. Treat it as a refinement, not a prerequisite.

**Calibration diagnostic:** the fitted profile integrated over bins should equal the nominal sweep width. A large discrepancy means the bin center m/z values are wrong, which invalidates everything downstream. Fail loudly rather than proceeding.

---

### 2.5 Design matrix, parallel isolation multiplexing (comb)

The parallel isolation scheme of Remes, MacCoss and Egertson (EP 4 535 399 A1; priority US application 18/377,481, 6 October 2023) isolates, in a single acquisition, a set of non-contiguous isolation sub-windows drawn from a grid of isolation window units, and steps that comb across the precursor range so each unit is analyzed at least twice per cycle. The published example uses four sub-windows of 20 Th separated by one-unit gaps: 80 Th of isolated width spread over a 120 Th span, with each unit sampled by four different acquisitions.

**This requires no change to the forward model.** `y = A x` never assumed the isolated range was contiguous. Row *i* of `A` simply has ones at the scattered column positions covered by that acquisition's comb rather than at a run of adjacent positions. The bin construction of Section 2.2 (sorted union of observed boundaries) works unchanged, as does the empirical edge modeling, and the patent's own note that soft-edged or sinusoidal isolation profiles should demultiplex better than square ones maps directly onto the fractional-`A` machinery built for scanning quadrupoles in Section 2.3. One code path serves both.

Three things do change, and one of them is a significant gain.

**1. `A` is still a convolution operator, so the fast solver survives intact.** When the comb is translated by one unit per acquisition, `A` remains Toeplitz, generated by a sparse indicator sequence rather than a run of ones. The example comb is `h = [1,1,0,1,0,1]` instead of `[1,1,1,1]`. Every performance decision in Sections 6 and 7 depended on `A` being shared across all fragment channels and RT points within a group, not on it being banded. Precomputed factorizations, tiered dispatch, and lane-parallel SIMD all carry over without modification. Only the dimensions grow.

**2. The conditioning improves, and there is a design criterion for it.** Section 3 shows the contiguous moving sum `[1,1,...,1]` has exact zeros in its transfer function at the *k*-th roots of unity, which is the source of the *k*-1 rank deficiency and the alternating-bin ringing artifact. A sparse comb has a different transfer function:

```
H(w) = sum over offsets n in S of exp(-i*w*n)
```

and generically **has no zeros on the unit circle at all.** For the example comb `S = {0,1,3,5}`, `H(pi) = 1 - 1 - 1 - 1 = -2`, where the contiguous four-window comb would be exactly zero. The system becomes genuinely invertible rather than relying on nonnegativity to rescue it.

That turns the patent's qualitative motivation, that gaps increase the diversity with which each unit is sampled, into a number that can be computed and optimized:

```
condition number of the circulant  =  max|H(w)| / min|H(w)|,  with max|H| = |S|
```

**Choose the sub-window offset set to maximize `min|H(w)|` over the unit circle.** This is the same flat-spectrum criterion used in Hadamard transform spectrometry, and it gives Osprey two capabilities worth having: it can report the conditioning of whatever comb an acquisition actually used, and it can rank candidate combs before anyone acquires data. A scheme designer currently has to guess which gap pattern demultiplexes well; this makes it a calculation.

**3. Locality is lost, and that is what it costs.** Every streaming and grouping decision in Sections 6.3 and 8 assumed the units coupled by an acquisition are adjacent. A comb couples units up to its full span apart, so:

- The demux group becomes all acquisitions whose comb touches any unit in the block, and the block must span the comb, not *k* bins. For the published example that is roughly 6 units plus halo instead of 2, so `A` grows from about 3x3 to about 12x18. Still small, still well inside the regime where the SIMD strategy of Section 7.2 beats a general BLAS, but four times the arithmetic per solve.
- The acquisition-order ring buffer of Section 8.2 must hold the comb span in cycles rather than `2k + cyclesInBlock`. With sub-cycling (the patent's dual and triple sub-cycle orderings) the required span is shorter in wall time but touches more acquisitions, so size the buffer from the acquisition schedule rather than from a constant.
- Output routing is unaffected, since demultiplexed records still land in narrow contiguous bins.

**Variants that need no special handling.** Sub-cycle orderings change only which acquisitions land in a group. Combs that vary through the gradient, or unit widths that vary with m/z, are covered by the rule already mandated for variable-width Astral schedules: build `A` from the observed windows, cache one factorization per distinct geometry. Random or non-sequential comb ordering is fine and in fact tends to improve `min|H|`. The ion mobility extension in the patent is the same algebra with the mobility axis substituted for m/z, and would need reader work rather than solver work.

**Where the ion-budget analysis lands.** The comb isolates a large total width, 80 Th in the example, which makes an acquisition more likely to be AGC limited. By Section 6.2 item 5 that is the regime where wide isolation costs per-measurement ion counts and pushes measurements toward the reporting floor. The scheme is therefore best matched to a counting detector, which is consistent with its ion-trap implementations, and the floor analysis should be run per instrument configuration before assuming the sensitivity gain survives to the demultiplexed output.

---

### 2.6 Design matrix, random co-isolation multiplexing (MSX)

MSX (Egertson JD, Kuehn A, Merrihew GE, Bateman NW, MacLean BX, Ting YS, Canterbury JD, Marsh DM, Kellmann M, Zabrouskov V, Wu CC, MacCoss MJ. *Nat Methods* 2013, 10(8), 744-746, doi:10.1038/nmeth.2528; PMC3881977) is where the demultiplexing effort started, and it is the most general case in this document. Each MS2 event co-isolates a randomly chosen subset of narrow windows drawn from the precursor range, and each narrow window is sampled by several events per cycle. Demultiplexing recovers the narrow window specificity from spectra that each isolated many times that width. Thermo RAW files record the selected precursors for these events in the scan header, so the incidence pattern is recoverable per scan.

**What carries over unchanged:** the forward model, the solver, the tiered dispatch, the SIMD lane strategy, and the caching of one factorization per distinct pattern.

**What is different:**

- **`A` is not Toeplitz along m/z.** Random selection destroys the translation structure that the staggered and comb cases retain, so the frequency-domain analysis of Sections 3 and 2.5 does not apply *to the precursor axis*. Use the singular value decomposition directly: report `sigma_min(A)` and the condition number, and define the artifact direction as the right singular vector belonging to `sigma_min`. This is why the ringing diagnostic in Section 3 is stated in singular-vector form rather than as a period-*k* test. The general form covers all three schemes; the alternating-bin pattern is just what it reduces to for a contiguous moving sum.

- **The schedule is nonetheless strictly periodic in time, and that is worth a great deal.** The pattern is not generated on the fly. Random selection happens once, at method creation, and the resulting schedule then repeats every cycle for the whole run. `A` is therefore a fixed, known, designed artifact rather than something to be inferred anew. Section 2.6b covers what follows from that.
- **Locality is gone entirely.** A random subset couples bins anywhere in the precursor range, so the demux group is the whole cycle. This actually simplifies streaming, since the unit becomes one cycle rather than a sliding block, but `N` grows to the full window count and the per-solve cost rises accordingly. Exhaustive active-set enumeration is out of the question at this size; use Lawson-Hanson seeded from the unconstrained solution, relying on solution sparsity for fast convergence.
- **Per-window fill times are the norm, not an edge case.** On an Orbitrap the co-isolated windows are accumulated sequentially into the C-trap before a single analysis, so each window can receive its own accumulation time, particularly under AGC control. Section 2.0 governs: `A[i][j] = tau_ij / IT_i`, and assuming equal fills when they are not is a correctness bug rather than an approximation. This is the single most important thing to get right for MSX support.

### 2.6b Exploiting schedule periodicity

The MSX incidence pattern repeats exactly, cycle after cycle, for the duration of the run. Five consequences, in rough order of value.

**1. One factorization for the entire run.** Not one per group or per geometry: one, full stop. Every precomputed object in Section 6.3, including the pseudoinverse and any active-set subset factorizations, is computed once at startup and reused for every cycle and every fragment channel in the file. This is the cheapest case in this document by a wide margin.

**2. The retention-time interpolation weights are also constants.** Section 4.1 requires interpolating each contributing event onto the target time before solving. With a fixed repeating schedule, every event's offset relative to cycle start is identical in every cycle, so the spline weights are the same for every cycle and every channel. Precompute them once alongside the factorization.

**3. Interpolation and demultiplexing fuse into a single operator.** Since both the interpolation weights and `A` are constant, their composition is a single fixed matrix. Applying one fused operator is both faster and more accurate than interpolating and then solving, because it avoids materializing an intermediate whose errors the solver then has to absorb. This is available only because the schedule is periodic, and it is the strongest argument for treating periodicity as a design feature rather than an incidental property.

**4. Batching extends across the whole run, not just within a group.** Section 7.2 relies on `A` being shared across right-hand sides. With a fixed pattern that sharing spans every cycle in the file, so the batch dimension is limited only by memory rather than by group boundaries. Combined with tier-homogeneous compaction (Section 7.4) this is the ideal case for the lane-parallel kernel.

**5. The pattern is recoverable from the method, and verifiable from the data.** Prefer reading the schedule from method metadata where the RAW file exposes it, rather than inferring it from scan headers. Either way, verify it: read many cycles and confirm the incidence matrix is constant. A mismatch means either a mid-run method change or a misparse, and both are worth failing on rather than silently averaging over.

**What periodicity does not fix.** Stacking consecutive cycles adds no new information about precursor mixing, because every cycle contributes identical rows. Rank deficiency is a property of the pattern, not of how many times it is repeated.

**A design option this suggests.** If conditioning at a given multiplex level is inadequate, rotate among *P* distinct patterns on a super-cycle of *P* cycles instead of repeating one. Over a super-cycle the effective row set is *P* times larger and genuinely distinct, which improves `sigma_min` directly. The cost is temporal: the contributing measurements now span *P* cycles rather than one, so retention-time skew grows and Section 4.1's interpolation does more work. This is the opposite trade from the sub-cycle orderings in the parallel isolation patent, which spend acquisition diversity to buy temporal sampling. Both knobs exist, they pull against each other, and which is worth more depends on cycle time against chromatographic peak width. Worth evaluating before assuming a single repeating pattern is optimal.

**Design criterion.** As with combs, the incidence pattern determines conditioning, and here it is directly `sigma_min` of the binary incidence matrix. Osprey should report it per file. Random selection is convenient but not optimal, and a pattern chosen to maximize `sigma_min` at fixed multiplex level would demultiplex better than a random one at no acquisition cost. That is a cheap, testable improvement to an acquisition scheme rather than to a solver.

---

## 3. Conditioning: why this works at all

This section describes the contiguous staggered case, which is the worst-conditioned of the three schemes. Comb acquisition (Section 2.5) can escape the rank deficiency entirely by design, and the argument below is what it escapes from.

The *k*-fold staggered design matrix is a moving-sum operator. Its discrete transfer function `[1,1,...,1]` (*k* ones) has exact zeros at frequencies 2*pi*m/k for m = 1..k-1. The unconstrained inverse therefore has infinite gain on alternating patterns with period *k*, and over a finite precursor range the system is rank-deficient by exactly *k*-1.

Two things make the problem well posed:

1. **Nonnegativity.** The null-space directions are sign-alternating, so they cannot be added to a nonnegative solution without driving some component negative. The constraint is not a nicety; it is the regularizer.
2. **Sparsity.** For any given fragment m/z channel, typically one and rarely more than three precursor bins actually contribute. Active-set NNLS returns sparse solutions naturally.

Consequences for the spec:

- Never solve the unconstrained problem and clamp. Clamping does not project onto the feasible set and leaves the null-space component in the answer.
- The signature of under-regularization is **alternating-bin ringing** with period *k*. Build a diagnostic that measures it (Section 10). State it generally rather than as a period-*k* test, since comb acquisitions have a different worst direction: the artifact lives along the right singular vector of `A` with the smallest singular value, and the diagnostic is the projection of the recovered solution onto it. For the contiguous moving sum that vector is the sign-alternating pattern, so the general form reduces to the specific one. The minimum singular value itself is the conditioning number to report (Section 2.5).
- **Not shipped: MS1-informed bin masking.** The idea is that if the MS1 survey at that retention time shows no isotope envelope consistent with any charge state in bin *j*, one could fix `x_j = 0` and drop the column, converting a rank-deficient system into an overdetermined one. It is tempting because it directly attacks the *k*-1 rank deficiency. **It is wrong, and not merely risky, because it gates the more sensitive measurement on the less sensitive one.** MS2 is roughly an order of magnitude more sensitive than MS1 in DIA: the survey scan spreads its AGC budget across the entire precursor range, while an MS2 event spends the same budget on a window a few Th wide, so a given precursor claims a far larger share of the ions. On an Orbitrap Astral the gap is wider still, since MS1 sits on the image-current Orbitrap with the charge floor of Section 6.2 while MS2 sits on a counting detector with essentially no floor.

  The consequence is not an occasional accident. Masking would systematically delete real MS2 signal for precisely the low-abundance precursors that fall below MS1 detection, which are the ones interference removal is supposed to rescue, and it would do so silently: the output would look clean. It also couples MS2 demux to MS1 feature-detection parameters, which are currently independent. This is not an option to expose, and it is not a v2 default. It is a general caution against any MS1-gated logic in the MS2 path.

---

### 3.1 Does a fragment channel assume a single precursor origin?

No. `x` is a vector over precursor bins and NNLS returns a nonnegative solution that may have several nonzero components, so a fragment channel receiving contributions from two or more precursors in different parts of the isolation window is represented exactly, not approximated. Nothing in the formulation forces a single origin. Three qualifications matter in practice.

**1. Mixtures are the hard case, and how hard depends on the scheme.** Section 3 establishes that nonnegativity plus sparsity is what makes the rank-deficient staggered system solvable. That regularizer is precisely what penalizes multi-bin solutions. Separating a genuine two-bin mixture requires distinguishing columns of `A` that may differ in only one row, so the discrimination rests on the ion count in that single event, whereas detecting a single origin uses all *M*. **Resolving a mixture therefore costs signal-to-noise that detecting one does not.**

Resolvability tracks `sigma_min(A)` directly, which is why the spec reports it:

- **MSX random co-isolation** is the best case. Each window has a distinctive incidence signature across the cycle, the matrix is well conditioned and typically full rank, and mixtures separate cleanly. This is the regime the original method was designed for.
- **Comb parallel isolation** is good, since Section 2.5 shows the gaps remove the unit-circle zeros.
- **Staggered at k = 2 is the worst case in this document.** Two measurements, adjacent bins that differ minimally, and a rank deficiency of one. Expect mixtures to be collapsed toward the sparser explanation. When they are, the error is not random: intensity is attributed wholly to one bin, which is a bias, not noise.

**2. The Tier 0 fast path infers single origin from zeros, and censoring can make that inference wrong.** Tier 0 concludes a single contributing bin when the only events with signal are those covering that bin. This is sound reasoning rather than an assumption: an event covering bin *j'* with zero intensity genuinely bounds bin *j'* at zero. But on Orbitrap platforms, Section 6.2 item 4 establishes that a reported zero means "below the reporting threshold," not zero. **A censored measurement can therefore make a genuine mixture look like a single origin, and Tier 0 will accept it without ever reaching the solver.** Gate the Tier 0 test on the censoring threshold, not on exact zero: require the missing rows to be confidently zero given `t_i`, and route the ambiguous cases to Tier 1. This is a correctness fix, not a tuning parameter, and it costs some of the Tier 0 share measured in Section 7.4.

**3. The dominant real mixture is not coincidental fragment sharing.** Two unrelated peptides sharing a fragment m/z within a few ppm happens, most often for short fragments, immonium ions, common neutral losses, and peptides from the same protein. But there is a far more common source, and it applies to every peptide rather than a subset.

**A precursor's isotope envelope spans several Th.** A 2+ tryptic peptide carries meaningful M+1 and M+2 intensity across roughly 1 to 1.5 Th, more for larger peptides. Once demux produces bins of 1 to 2 Th, **the isotope envelope of a single peptide routinely straddles a bin boundary**, so that peptide contributes to two adjacent bins with correlated fragment patterns. This is not an edge case; it is the normal condition for narrow bins.

Consequences that must be handled downstream rather than in the solver:

- The recovered `x` for a peptide's fragments is split across adjacent bins according to which isotopologues fall where. Scoring a target precursor against only the bin containing its monoisotopic mass will systematically lose the intensity carried by higher isotopologues in the neighbouring bin.
- Extraction for a target precursor should therefore **sum across the bins its isotope envelope occupies**, computed from the precursor mass and charge, rather than selecting a single bin.
- This also means the two adjacent bins are genuinely correlated by construction, which is worth remembering when interpreting the FDR concern in gate G6.5. Demultiplexed records are not independent, and here the dependence has a known physical cause.
- **Diagnostic:** for confidently identified precursors, report the fraction of fragment intensity recovered outside the monoisotopic bin. It should track the predicted isotope distribution. A large discrepancy indicates either a bin-center calibration error or a demux bias, and it is a sensitive test of both.

## 4. The retention time axis

The measurements that constrain a precursor bin do not all arrive at the same instant. How that is handled is the single largest determinant of quantitative accuracy for stepped acquisitions, and the naive treatment gives away the main advantage of staggering.

### 4.1 Staggering improves chromatographic sampling

The temporal offset between staggered sets reads at first as a nuisance to be undone. It is an asset, and the design follows from taking that seriously.

Compare two methods at the same acquisition rate and the same effective bin width:

| | Acquisitions per repeat | Repeat period | Times each **bin** is measured per period |
|---|---|---|---|
| Narrow, non-staggered | 2W windows of width w/2 | R | 1 |
| Staggered | W of width w, plus W offset by w/2 | R | **k** (here 2), spaced R/k |

Same acquisition count, same period. But each bin is covered by one window from each set, and those acquisitions are interleaved in time. Simulated with R = 1.0, the acquisitions containing a given bin have median spacing **0.500** against 1.000 for the narrow method.

**A precursor bin's chromatogram is sampled k times more densely under staggering than under narrow windows at the same acquisition rate.** The wide windows also collect more ions per acquisition in the injection-time-limited regime (Section 6.2). Staggering buys better temporal sampling and better ion statistics at once; the price is that the measurements must be unmixed.

### 4.2 Sampling adequacy, and what the Nyquist concern is really about

A natural objection: DIA cycle times are already chosen near the Nyquist limit for the chromatographic peak, often around six points per peak. Dividing the cycle into k sub-cycles leaves each individual window sampled once per full cycle, so each staggered set looks severely undersampled.

The observation is correct but concerns the wrong quantity. **A window's chromatogram is not what is being measured; a bin's is.** By 4.1 the bin is sampled k times better, not k times worse. What the objection does correctly identify is that any scheme which estimates a *window's* chromatogram at times it was not acquired will pay heavily when cycle time is marginal.

Quantified, since the size of that penalty sets the design. Exponentially modified Gaussian with realistic tailing, 7-point monotone cubic Hermite, error as a percentage of local peak height, apex phase randomized:

| Points per FWHM per window | k=2 | k=3 | k=4 | No interpolation at all |
|---|---|---|---|---|
| 8 | 0.4% | 0.5% | 0.5% | 28% |
| 6 | 0.9% | 1.2% | 1.2% | 38% |
| 4 | 3.3% | 4.1% | 3.8% | 61% |
| 3 | 8.8% | 9.8% | 8.6% | 89% |
| 2 | 34% | 31% | 25% | 158% |
| 1.5 | 79% | 63% | 49% | 243% |

Three readings:

- **There is a cliff between 3 and 2 points per FWHM.** The degradation is abrupt rather than gradual.
- **Higher k is not worse**, and in the undersampled regime is slightly better, because the gap being spanned is R/k. The damage comes from per-window cadence, never from the offset itself.
- **Ignoring the offset is an order of magnitude worse than interpolating across it.** Whatever else is true, using a neighbouring scan at face value is not an option.

**The operative requirement is on the bin, not the window: at least 4 points per FWHM after the k-fold interleave, preferably 6.** That is the same requirement DIA already carries for quantification, and it is k times easier to satisfy than the per-window figure.

### 4.3 Solve on the acquired time axis

Do not evaluate any window at a time it was not measured. Model each bin's chromatogram as a smooth function and fit every measurement where it actually occurred:

```
y_i(t_i)  =  sum_j A_ij  x_j(t_i)        each acquisition i at its own time t_i
x_j(t)    =  sum_m c_jm phi_m(t)         cubic B-spline basis, knots at peak-width scale
```

Solve for `c` by nonnegative least squares over a retention-time block with a second-difference roughness penalty. Nothing is interpolated; the fitted `x_j(t)` may afterwards be evaluated anywhere, supported by measurements at spacing R/k.

**Why the smoothness prior is load-bearing.** Per repeat period there are 2W measurements and 2W bins, but free values on the fine grid would need 2W·k unknowns, so the pointwise problem is underdetermined by exactly k. Chromatographic smoothness closes that gap: an LC peak needs far fewer degrees of freedom than one per time point. With knots at roughly the peak width the system is comfortably overdetermined.

Measured on a six-bin simulation with coeluting interferences in neighbouring bins:

| | Area error | Apex error (units of R) |
|---|---|---|
| Interpolate then solve, noiseless | +0.22% | +0.490 |
| Acquired-axis fit, noiseless | −0.00% | +0.000 |
| Interpolate then solve, 300 ions | −2.54% | +0.490 |
| Acquired-axis fit, 300 ions | −3.09% | +0.390 |

Area is comparable and at 300 ions the fit is marginally worse on area, within this test's noise. **The apex column is the informative one.** Interpolate-then-solve reports apex on a grid of spacing R and carries roughly half a cycle of quantization; the acquired-axis fit resolves it exactly when noiseless, because it is supported at R/2. Peak boundaries and any shape-based scoring inherit that difference, and none of it shows in an area comparison.

**Caveat.** Knot placement against real peak-width variation across a gradient is untested and is the obvious failure mode: too few knots bias the shape, too many restore the underdetermination. Fit knot spacing per file from measured peak widths rather than fixing it.

### 4.4 Fallback: per-window interpolation

Where the acquired-axis fit is unavailable or a reference is needed, interpolate each window's own chromatogram onto the target time using monotone cubic Hermite with Fritsch-Carlson tangents. Plain Catmull-Rom overshoots on sharp chromatographic edges, and injected intensity has to be attributed to some bin, which it will get wrong. Gather `cyclesInBlock` cycles (default 3) around the target and interpolate a whole channel batch at once, since the sample times are shared across channels within a window.

This is the approach taken in `pwiz/analysis/demux/OverlapDemultiplexer`. Retain it compiled as the reference implementation for gate comparisons; do not ship it as the default.

### 4.5 Scanning quadrupole

No retention-time treatment is required. At 858 Hz the M bins of a group are acquired within roughly 10 ms, three orders of magnitude below chromatographic peak widths.

The scanning case does have a distinct temporal effect that must not be confused with retention-time skew: the collision-cell lag in Section 2.3. That is a shift along the *sweep* axis, which is the m/z axis, and it belongs in `A`.


## 5. Fragment channel alignment

The solver needs the same fragment channel across all M events, but centroided m/z values differ slightly between events for the same true fragment. This is the least glamorous part of the design, the largest source of implementation bugs, and per Section 7.5 the hot path at high spectral density. It deserves more care than a tolerance constant.

### 5.1 Why the m/z moves, and why a fixed tolerance is wrong

Two distinct error sources, which need different treatment:

**Statistical jitter, which is intensity dependent.** The uncertainty in a centroid position scales as roughly `FWHM / (2.35 * sqrt(N_ions))`. At R = 40,000 and m/z 500, FWHM is about 12 mTh, so a 3-ion peak has a centroid error near 3 mTh (6 ppm) while a 300-ion peak is at 0.3 ppm. **A single fixed ppm tolerance is therefore wrong at both ends**: too loose for abundant fragments, letting neighbours merge, and too tight for weak ones, splitting real channels. Use an intensity-dependent tolerance

```
tol_ppm(N)  =  sqrt( a^2  +  b^2 / N )
```

where `a` is the calibration-stability floor (order 1 to 3 ppm) and `b` follows from resolving power. `N` is the ion count from Section 2.0, which is already computed. Fit `a` and `b` once per file from the spread of high-count clusters; do not ship them as constants.

**Systematic per-event offsets.** Distinct from jitter and more damaging, because it biases rather than blurs. Staggered Orbitrap acquisitions interleave scans with different total ion loads, so space-charge shifts differ between the events being linked. Long runs drift with temperature. If event *i* carries a systematic offset, symmetric clustering still nominally works but the representative is biased and, at larger offsets, clusters split cleanly into two.

**Correct offsets before clustering.** Estimate a per-event m/z offset from the abundant, unambiguous centroids shared across the group, apply it, then cluster. This is a small local recalibration and it removes the dominant systematic before the tolerance test ever runs. Report the fitted offsets; a drift that grows through the run is a real instrument observation, not a nuisance.

### 5.2 Linking algorithm

**Rejected: global fixed fragment grid.** Trivially vectorizable, but splits peaks across bin boundaries and forces a dense representation.

**Adopted: per-group union channel index.**

1. Gather centroids from all M events across the cycles in the block. Each spectrum is already m/z sorted, so this is a **k-way merge with a loser tree**, not a sort: O(total * log k), about 3 comparisons per element at k = 7. This is where the 3 ns per step in Section 7.4 comes from, and it is the right structure to optimize.
2. Apply the per-event offset correction from 5.1.
3. Single-linkage along m/z using the intensity-dependent gap test.
4. **Apply the same-event-duplicate test.** Each event contributes at most one centroid per true fragment, so a cluster containing two or more centroids from the same event is over-merged by construction. Split it at its largest internal gap and repeat. This is a structural constraint that pure gap-based clustering ignores, it is nearly free, and it is the main defence against single-linkage chaining through a dense region.
5. Assign channel ids by sorting representative m/z ascending, never by hash order, for determinism.
6. Emit a dense `M x C` matrix per cycle, zero-filled for absent peaks, plus an `int32` channel id vector.

**Err toward merging.** A split channel is worse than an over-merged one. Splitting gives two channels each with partial support, and both solve to confidently wrong halved answers with no diagnostic signature. Over-merging is caught by step 4 and shows up as elevated residuals. Bias the tolerance accordingly.

### 5.3 Missing peaks

A fragment below detection in one event yields no centroid. Zero-fill and do not impute. On the scanning TOF platforms a zero is genuine information: the precursor is not in the bins that only that event covers. On Orbitrap and Astral it holds only down to the reporting threshold, since lossy background removal censors low values before centroids are written; see Section 6.2 item 4 for the censored-row treatment.

### 5.4 Two consequences worth noting

**Demultiplexed m/z is more precise than the input.** The cluster representative is an ion-count-weighted pooled estimate over up to *k* independent measurements, so it carries roughly sqrt(*k*) better precision than any single centroid. Write the representative, not the per-event centroid, to the output record. Beyond the consistency argument for downstream XIC extraction, this is a free accuracy gain that should be visible as tightened fragment mass error distributions after demux, and it makes a good sanity check that the linking is working.

**Channel count control.** Cap C per group at `maxChannelsPerGroup` (default 4096). On exceeding it, drop the lowest-intensity clusters and record the count. In practice this triggers only on garbage spectra, and a rise in the counter is a useful signal that something upstream is wrong.

### 5.4b Unit-resolution instruments (Stellar and other linear ion traps)

Everything in 5.1 and 5.2 assumes centroids are precise to ppm and that a centroid corresponds to one fragment. On a unit-resolution radial-ejection linear ion trap, neither holds, and the failure mode is not the one the tolerance model was built for.

**The problem is blending, not jitter.** At roughly 0.5 to 0.7 Th peak width, fragments closer than about 1 Th are unresolved and produce a single centroid whose position is the intensity-weighted blend of its constituents. Because the M events in a group isolate different precursor sets, **the blend ratio differs between events, so the centroid moves for compositional reasons rather than statistical ones.** That shift can approach the separation of the blended fragments, far larger than any tolerance you would want to set, and unlike jitter it does not shrink with ion count. Proximity clustering cannot fix this, and a tolerance loose enough to absorb it would merge genuinely distinct channels.

**The linear model survives intact.** If channel *c* collects several true fragments, then `x_{j,c}` is simply the summed intensity of all fragments from precursor bin *j* that fall in channel *c*, and `y_{i,c} = sum_j A_ij x_{j,c}` still holds exactly. Demultiplexing recovers per-bin contributions to a blended channel, which is exactly what is wanted. Only the channel *definition* needs to change.

**Adopted for unit resolution: a fixed fragment grid with soft binning.** The grid I rejected in Section 5.2 for high-resolution data is the right answer here, because at unit resolution the information that clustering would recover does not exist in the first place.

1. Fixed grid at the instrument's resolution, on the order of 1 Th. Channel identity is the bin index. No clustering, no tolerance, no blend-shift sensitivity.
2. **Distribute each centroid's intensity between the two nearest bin centers in proportion to distance**, rather than assigning it wholly to the nearest. Hard assignment makes a centroid near a boundary jump discontinuously between events as the blend shifts, reintroducing the problem in a new form. Soft binning makes the assignment a continuous function of m/z, so a small shift produces a small change in both bins and the linear system stays consistent.
3. Grid width should be comparable to the peak width. Narrower buys nothing and increases splitting; wider needlessly merges.

**Three consequences, two of them good.**

- **The merge cost vanishes.** Section 7.5 shows channel merging matching or exceeding the solve on the fastest acquisitions. Fixed-grid binning is an index computation, not a k-way merge, so that entire term disappears. Unit-resolution demux should be the cheapest case in this document.
- **Demux is worth *more* here, not less.** With unit-resolution fragments there is much less selectivity available in the fragment dimension, so two peptides' fragments landing in one channel is common rather than exceptional. Selectivity in the precursor dimension is therefore doing proportionally more of the work, which is the argument for demultiplexing in the first place.
- **Channel count is bounded by the grid**, roughly 1000 to 1300 channels over a typical fragment range, which caps the per-group work and makes the Section 7.5 density sensitivity largely moot.

**Detector and regime.** The Stellar is an ion-counting detector and Hsu et al. Table 1 puts its `alpha` at 0.97, meaning reported intensities are already essentially in ions/sec. There is no image-current thermal floor, so by Section 6.2 item 5 it sits with the Astral and the 8600 in the favorable camp rather than with the Exploris. The countervailing concern is space charge: an ion trap has a hard capacity limit, so the AGC target is bounded and wide isolation reaches it quickly. That pushes toward the AGC-limited regime where wide-window-plus-demux loses its advantage. **Measure the crossover per method on this platform specifically; do not inherit the roughly 500 ng figure from the Orbitrap Astral.**

**Acquisition schemes.** Parallel waveform isolation with notched broadband waveforms makes the comb scheme of Section 2.5 and the random co-isolation of Section 2.6 directly implementable on a linear ion trap, and the parallel isolation patent describes exactly these ion-trap configurations. Section 2.0 is therefore not optional here: co-isolated sub-windows are accumulated sequentially into the trap and can receive different fill times.

One practical note that does not affect the demux algebra but does affect what is available to demultiplex: the low-mass cutoff means fragments below roughly a third of the precursor m/z are not retained, so the usable fragment channel set is narrower than the grid suggests.

### 5.4c Profile-domain demultiplexing for linear ion traps

For Stellar and similar instruments, demultiplex the **profile** data and centroid afterward. This supersedes the fixed-grid centroid approach of 5.4b, which becomes the fallback for files acquired in centroid mode.

**Why this order is correct, not merely convenient.** Demultiplexing is linear; centroiding is not. Performing the nonlinear step first destroys information that the linear step could have used, and the loss is not recoverable. Concretely: two fragments 0.4 Th apart from *different precursors* centroid to a single peak at the weighted mean. Demultiplexing that centroid can only split its total intensity between precursor bins; the two distinct m/z values are gone. Demultiplex the profile first and each bin carries its own peak at its own m/z, so centroiding afterward recovers both. **In the precursor-separable case, profile-domain demux delivers fragment m/z resolution beyond the instrument's nominal resolving power**, by using the precursor dimension to deconvolve the fragment dimension.

**The enabling fact is that the grid is exact.** Centrix documents the Stellar profile grid spacing as fixed by firmware per scan rate, 1/8 Th at the 125 kTh/s standard DIA MS2 setting with 0.8 Da FWHM. Spectra acquired at the same scan rate therefore share an identical m/z axis, so profile demux is bin-wise with no resampling, no clustering, no tolerance, and no linking step at all. **Verify scan rate is constant across the events in a group**; a mixed-rate method would require resampling onto a common grid, which is linear and composes correctly but blurs.

**Pipeline.** Vendor read → profile demux, one small NNLS per grid point per group → centroid each demultiplexed bin → write centroids to the cache. The profile is consumed, never persisted. For staggered, comb, and MSX ion-trap acquisitions `A` comes from declared windows and fill times with no fitted kernel, so the two-pass structure of Section 9.1c is unnecessary and the passes fuse. This matters: persisting profile would be roughly 14 GB for a 30 min run before sparsification.

**Cost.** For a 30 min Stellar DIA run at 125 kTh/s over a 200-1200 Th fragment range: 8000 grid points per spectrum, of which perhaps 15 to 25% lie in signal regions, so about 1600 live points; roughly 48 events per cycle and 0.6 s cycles, so about 2950 cycles. Sliding groups give about 227 M solves at roughly 8 ns each, so **under 2 s, and about half that with blocked stepping.** The merge term is zero. Profile-domain demux is cheaper than the centroid-domain case despite operating on far more points, because linking is what costs money and there is none.

**Why this should make centrix faster, which is the non-obvious part.** The centrix algorithm document states that all detected regions go to LASSO with no fast-path shortcut, precisely because two overlapping signals under 1 Da apart can look like a single merged peak at the profile level and there is no way to tell from one spectrum. **Demultiplexing answers that question from a different axis.** In a DIA experiment the overlapping signals centrix exists to resolve very often originate from different precursors, and demux separates those into different bins *before* centroiding. Three consequences:

1. **The fast path becomes safe.** After demux, a region whose recovered profile is consistent with a single Gaussian at the known σ, and whose demux solution concentrates support in one bin, can be centroided by a direct shape fit instead of LASSO. The residual test is O(n) against a LASSO solve, and the fallback to LASSO on failure preserves correctness. This turns "no fast-path possible" into "fast path usually safe."
2. **The remaining LASSO problems get smaller.** Solver cost grows superlinearly with the number of active components in a region. Splitting a crowded region's components across *k* bins reduces the active count per problem, and the hardest regions, which dominate runtime, are exactly the ones demux simplifies most.
3. **The noise refinement pass may become unnecessary.** Centrix runs a second pass to refine sigma(m/z) from pass-1 residuals and selectively re-fits. After demux the per-bin variance is analytically predictable, since Poisson variance in the input propagates through the design matrix as `(A^T W A)^-1`. Handing centrix a computed per-bin sigma instead of an estimated one could remove the refinement and selective re-fit entirely.

### 5.4d Joint demux and centroiding (the target design for profile data)

Solve demultiplexing and centroiding as one problem rather than in sequence. Sequential is retained as the reference implementation for validation, not as the plan.

**Formulation.** Within a signal region, with `B` the Gaussian basis at grid positions and `beta_j` the coefficients for precursor bin *j*:

```
x_j[p] = sum_q B[p,q] beta_j[q]          (peak model)
y_i[p] = sum_j A_ij x_j[p]               (demultiplexing)
=>  y_i[p] = sum_j sum_q A_ij B[p,q] beta_j[q]
```

Minimize `0.5 * ||y - (A kron B) beta||^2_W + lambda * ||beta||_1` subject to `beta >= 0`. The design matrix is the **Kronecker product `A kron B`**, which is what makes this tractable rather than merely elegant. Note that `A` is independent of fragment m/z (precursor transmission and fill time do not depend on where the fragment lands), so `B` is shared across all bins and the Kronecker structure is exact, not approximate.

**Why it is cheap.** The Gram matrix factorizes:

```
(A kron B)^T (A kron B)  =  (A^T A) kron (B^T B)
```

`A^T A` is tiny and dense, at most 19x19 and typically 5x5. `B^T B` is the banded Toeplitz matrix centrix already exploits, roughly 6 to 15 nonzero entries per row. Coordinate descent then needs no large objects:

- **Gradient.** Precompute `z_i = B^T r_i` per event, which is *M* banded matvecs. Then `g[j,q] = sum_i A_ij z_i[q]`, a small `N x M` by `M x Q` GEMM. No large matrix is ever formed.
- **Diagonal.** `d_j = (A^T A)_jj * gram0`, constant in *q* for a uniform grid.
- **Update.** `beta[j,q] <- max(0, beta[j,q] + (g[j,q] - lambda) / d_j)`.
- **Residual.** Changing one coefficient touches `r_i[p] -= A_ij B[p,q] delta` over the band, costing `M x bandwidth`.

So the per-update cost is *M* times a centrix update, and the active set size is unchanged, since each true fragment occupies exactly one `(j,q)` cell. Against sequential, which runs *N* separate LASSO solves, one per demultiplexed bin, **joint is plausibly cheaper as well as more accurate.** For staggered ion trap data with `M = 3` and `N = 5` locally, it should be close to a wash on arithmetic and a clear win on quality.

**Four things joint gets that sequential does not.**

1. **The peak-shape prior constrains the demux.** Sequential solves each grid point independently, so a noisy point in a peak tail is poorly determined on its own. Jointly, that point's bin assignment is constrained by the whole peak it belongs to.
2. **L1 fixes the demux rank deficiency.** Section 3 establishes that the staggered design matrix is rank-deficient by *k*-1 and that nonnegativity alone is the regularizer. In the joint formulation the L1 penalty applies in the product space and is a strictly stronger regularizer than nonnegativity alone. **This is a free solution to the conditioning problem that motivated most of Section 3**, and it arrives from the peak model rather than from anything precursor-side.
3. **No ragged intermediate.** Sequential produces a demultiplexed profile that carries NNLS noise and shape artifacts, which the centroider then has to interpret. Joint never materializes it.
4. **Lambda comes from a well-characterized place.** Noise lives in the event domain, where Section 2.0 gives Poisson variance analytically from ion counts and fill times. That is a better basis for the sparsity penalty than centrix's current residual-based estimate, and it removes the need for the pass-2 noise refinement rather than merely informing it.

**What it costs.**

- **The Section 7 parallelization axis changes.** Lanes cannot be fragment channels, because the joint solve couples across m/z within a region. Signal regions are mutually independent, so parallelize over regions across threads and use SIMD within a region for the banded matvecs. Determinism follows the same rules: fixed coordinate ordering, deterministic active-set tie-breaking to lowest index, no cross-region interaction.
- **It is a genuinely larger implementation** than either piece alone, and it is the only place in this document where two subsystems are fused rather than composed. That is the argument for building sequential first as a reference, not for shipping it.
- **It applies only to profile data**, so the centroid-domain paths of Sections 5.2 and 5.4b are still required for centroid-mode files and for the high-resolution platforms.

**Build order.** Sequential first, purely as the reference implementation. Then joint, gated against it: on data where fragments are well separated the two must agree closely, and where they diverge the joint result must be demonstrably better against synthetic truth. Keeping sequential compiled afterward serves the same role that the Phase 1 scalar solver serves for the SIMD path in gate G3.4.

**Profile acquisition is a method requirement.** None of this works on files acquired in centroid mode, and profile acquisition costs substantially more disk. Detect the mode and fall back to 5.4b with a clear warning rather than failing.

### 5.5 Gates specific to linking

| ID | Test | Threshold |
|---|---|---|
| G5.6 | Same-event-duplicate violations surviving in the final channel index | 0 |
| G5.7 | Synthetic data with known fragment identity and injected jitter: linking precision and recall | > 0.99 at 3 ions/peak |
| G5.8 | Fitted `a` and `b` of the tolerance model, plus per-event offsets, reported | emitted |
| G5.9 | Fragment mass error spread after demux versus before | narrower |
| G5.10 | Fixed-tolerance versus intensity-dependent tolerance on synthetic data | intensity-dependent strictly better at low ion counts |
| G5.11 | Unit-resolution mode auto-selected from instrument metadata and reported resolving power | correct on Stellar and on a high-res file |
| G5.12 | Soft versus hard binning on synthetic unit-resolution data with blended fragments and shifting blend ratios | soft strictly better |
| G5.13 | Unit-resolution grid width sweep: recovery error versus grid width | minimum near the peak width |
| G5.14 | Merge cost on a unit-resolution file | approximately zero; no k-way merge invoked |
| G5.15 | **Profile demux then centroid, versus centroid then demux**, on synthetic data with two fragments <1 Th apart from different precursors | profile-first recovers both m/z; centroid-first cannot |
| G5.16 | Profile grid identity across events in a group | exact match, or resampling path invoked with a warning |
| G5.17 | Centrix fast-path safety: regions taking the shape-fit path versus LASSO ground truth | centroid m/z agreement within 0.01 Th, 100% |
| G5.18 | Centrix wall time, demuxed input versus undemuxed | faster, and report the fast-path fraction |
| G5.19 | Analytic per-bin sigma from `(A^T W A)^-1` versus centrix pass-2 estimated sigma | agree within 20%; if so, pass 2 may be skipped |
| G5.20 | Centroid-mode file detected and routed to the 5.4b fallback with a warning | correct |
| G5.21 | **Joint versus sequential** on well-separated synthetic fragments | agree within 0.005 Th and 2% intensity |
| G5.22 | Joint versus sequential on blended fragments from different precursors, against synthetic truth | joint strictly better |
| G5.23 | Joint solve conditioning: recovery at k=2 without any explicit regularization beyond L1 and nonnegativity | ringing metric below the sequential path |
| G5.24 | Joint wall time per region versus N sequential LASSO solves | within 2x, target faster |
| G5.25 | Determinism of the joint solve across thread counts and region orderings | byte-identical |

---

## 6. The solver

### 6.1 Statement

Per channel, per cycle:

```
minimize || W^(1/2) (A x - y) ||^2   subject to   x >= 0
```

M is between 2 and about 13, N between 3 and about 19. These are tiny problems, and there are tens of millions of them. All performance work follows from that ratio.

### 6.2 Noise model and weighting

**Every platform in scope is ion counting.** The Astral is a multi-reflection TOF with single-ion detection and an accumulation trap under AGC control. The Orbitrap is likewise count-based. What differs between them is only a scale factor and the fact that the accumulation time varies per spectrum. There is no need for separate TOF and Orbitrap noise models.

Following the ions/sec calibration framework of Hsu et al. (*J. Proteome Res.* 2025, 24(11), 5742-5754, doi:10.1021/acs.jproteome.5c00593), reported intensity is proportional to ion current, not to ion count:

```
y = alpha * N / IT
```

where `N` is the number of ions, `IT` the injection or accumulation time, and `alpha` a scaling constant. Measured values (Hsu et al. Table 1, Glu[1]-Fibrinopeptide B):

| Analyzer | Instrument | alpha |
|---|---|---|
| Astral | Orbitrap Astral Zoom prototype | 1.31 |
| Astral | Orbitrap Astral | 1.53 |
| Orbitrap | Orbitrap Astral Zoom prototype | 10.30 |
| Orbitrap | Orbitrap Astral | 10.62 |
| Orbitrap | Exploris 480 | 10.95 |
| Orbitrap | Orbitrap Ascend | 9.40 |
| Orbitrap | Orbitrap Fusion | 15.44 |
| Ion trap | Stellar | 0.97 |
| Ion trap | Orbitrap Ascend | 0.98 |
| Ion trap | Orbitrap Fusion | 1.09 |

In every row the standard error is small, R-squared exceeds 0.998, and the intercept `sigma_o^2` is essentially zero. **A pure Poisson model is correct; there is no meaningful additive electronic noise floor to fit.**

**`alpha` is a property of the analyzer, not the file.** This table settles a structural question rather than merely supplying constants. The same physical Orbitrap Astral reports 1.53 through its Astral analyzer and 10.62 through its Orbitrap analyzer, roughly a sevenfold difference within one instrument. Since a DIA run on that platform puts MS1 on the Orbitrap and MS2 on the Astral, **a single per-file `alpha` is wrong and would misstate ion counts by nearly an order of magnitude for one of the two scan types.** Osprey must resolve `alpha` per scan from the analyzer that produced it. The same applies to tribrid instruments, where the Ascend reports 9.40 on its Orbitrap and 0.98 on its ion trap.

Two further cautions from the same table. Instruments sharing an analyzer design do not necessarily share `alpha`: the Exploris 480, Orbitrap Astral, and Orbitrap Ascend use the same Orbitrap analyzer but the Ascend differs, which the authors attribute to software. And `alpha` varies slightly with the calibration analyte. So a built-in table keyed on model is a starting default, not an answer, and the infusion calibration remains the way to get it right for a given instrument.

Two consequences, one of which reverses an earlier draft of this document:

**1. Do not normalize the model by injection time.** Reported intensity is already a rate. The mixing `A x = y` is linear in ion current, so it holds directly in reported intensity units regardless of how `IT` varies between cycles under AGC. Dividing rows by `IT` before the solve would be double-counting and would corrupt the system whenever staggered cycles had different fill times. Injection time enters through the weights only.

**2. Injection time and alpha belong in the variance.** Propagating Poisson variance in counts back to intensity units:

```
var(y_i) = alpha * y_i / IT_i     =>     w_i = IT_i / (alpha * max(y_i, floor))
```

`alpha` is constant within a file and cancels out of the relative weighting, so the working weight is simply `w_i = IT_i / max(y_i, floor)`. This is one expression that covers ZT Scan, SONAR, Astral, and Orbitrap. It also means the row weighting is nontrivial precisely in the stepped-staggered case, where AGC gives different cycles different fill times, and nearly uniform in the scanning case, where accumulation is fixed.

Multiply in the temporal proximity weight from Section 4.1.

**3. Work in ion counts for thresholds.** Although the solve runs in intensity units, every threshold in this spec should be expressed in ions, via `N = y * IT / alpha`. "Fewer than three ions" is a meaningful, instrument-independent statement; "below 1000 arbitrary units" is not, and does not transfer between an Astral and an Orbitrap file. Osprey should resolve `alpha` **per scan, from the analyzer that produced it** (defaulting to a table keyed on model and analyzer from the raw file metadata, overridable with `--alpha`), and express the Tier 0 noise floor, the sparsification floor in Section 8.4, and the diagnostics in Section 10 in ions.

**4. Orbitrap lossy compression makes zeros censored, not measured.** Orbitrap data are subject to a lossy noise-removal step before centroids are reported, so an absent peak means "below the reporting threshold", not "zero ions". Treating it as an exact zero over-constrains the system and biases the recovered bins downward. Handle censored rows as one-sided constraints: the residual contribution is `max(0, (A x)_i - t_i)` where `t_i` is the local reporting threshold, rather than `((A x)_i - y_i)^2`. In the active-set solver this is cheap, since a censored row simply drops out of the residual whenever the current solution already satisfies it.

**5. The Orbitrap has a hard charge-equivalent noise floor that scales with transient length.** Orbitrap detection is image-current based, and the dominant noise below the counting regime is thermal noise in the preamplifier, which is independent of signal. Makarov and Denisov (*J. Am. Soc. Mass Spectrom.* 2009, 20, 1486-1495, doi:10.1016/j.jasms.2009.03.024) measured this directly by detecting individual 20+ myoglobin ions and confirming quantized S/N. Their numbers:

- Full noise band of a standard Orbitrap preamplifier: **about 5 to 6 elementary charges at a 0.76 s acquisition, about 4 charges at 1.5 s.**
- The noise band is defined as 5 to 6 r.m.s. deviations of the thermal noise, and **peaks at S/N of 1 or below are not reported as peaks at all.**
- Signal from surviving ions was unchanged between 0.76 s and 1.52 s while the noise band fell as the square root of acquisition time.

This does not contradict item 1. The ions/sec calibration was derived from ratios of prominent fragment ions well inside the Poisson-dominated range, so it legitimately found no additive term there. The thermal floor lives below the range that calibration probed. Independent work on Orbitrap noise structure describes exactly this stratification: detector noise and a censoring algorithm dominating at low signal, counting noise at intermediate signal, other variation at high signal.

**The noise band is the censoring threshold.** Item 4 asked where `t_i` comes from. It is this: the reporting cutoff sits at S/N = 1 against a noise band of known charge equivalence. So

```
t_i (in charges)  =  N_0 * sqrt(T_0 / T_i)      with N_0 = 5.5 at T_0 = 0.76 s
```

converted to intensity units through `alpha` and `IT_i`. Confirm `T_i` against the resolution-to-transient table for the actual instrument rather than assuming.

**The consequence for DIA is severe and is the single most important constraint in this document.** Signal is constant in transient length while noise falls only as its square root, and DIA runs short transients for speed. Extrapolating the 2009 standard-field measurement:

| MS2 transient | Approx. floor (charges) |
|---|---|
| 512 ms | ~7 |
| 256 ms | ~9 |
| 128 ms | ~13 |
| 64 ms | ~19 |
| 32 ms | ~27 |

High-field analyzers gain roughly 1.4x in S/N and preamplifiers have improved since 2009, so treat these as an upper bound, perhaps 1.4x to 2x optimistic. Even so, a typical Orbitrap DIA MS2 scan has a reporting floor on the order of **10 to 20 charges**, not 6.

**Converting the floor to ions.** The floor is in charges, but the quantity being demultiplexed is a fragment channel, so what matters is the charge of the *fragment*, not the precursor. At the ~19 charge floor for a 32 ms high-field transient:

| Fragment charge | Ions needed to clear the floor |
|---|---|
| 1+ | ~19 |
| 2+ | ~9 to 10 |
| 3+ | ~6 |

For tryptic 2+ precursors the b and y ions are predominantly singly charged, so **~19 ions per fragment channel is the operative number** for most of the proteome. Higher precursor charge states shift some fragment population to 2+ and lower the effective floor, a modest but real advantage for 3+ precursors. Multiply by the number of fragments a precursor needs above the floor to be scored, and the per-precursor requirement at the chromatographic apex lands in the low hundreds of ions.

**Correction to an earlier framing in this document: demux does not divide the ion budget.** Each of the *k* overlapping events is a separate acquisition, and the target precursor's ion count in each is set by its own ion current times that event's injection time. Demux combines *k* measurements of the same signal rather than splitting one. That is precisely the ion-statistics advantage of a wide window which motivates the whole exercise. The floor bites through a different mechanism, and which mechanism applies depends on the acquisition regime:

- **Injection-time limited (low load).** The AGC target is never reached, so `IT` is fixed by the method and window width does not change it. The target precursor contributes the same ions per event whether the window is wide or narrow. Wide window plus demux is then a **genuine win**: *k* independent measurements of the same signal, approaching a sqrt(*k*) precision gain before conditioning losses. The censoring floor applies equally to the narrow-window alternative, so it does not penalize demux.

- **AGC limited (high load).** A window *k* times wider carries roughly *k* times the total ion current, so AGC reaches its target in roughly `IT/k`. The target precursor's ions per event drop by about *k* while the number of events rises by *k*. Total target ions across the group is a wash, but each individual measurement now sits *k* times closer to the reporting floor, and **a censored measurement cannot be recovered by any solver.** In this regime demux is worse than simply acquiring narrower windows directly.

The practical reading: wide-window-plus-demux is favorable exactly where the method is underfilling and unfavorable where AGC is being met. Hsu et al. locate that crossover concretely. With an AGC target of 20,000 ions on the Orbitrap Astral, median ion counts reach the target at 500 ng HeLa input for the 3 Th / 6 ms and 4 Th / 8 ms methods, while at 200 ng underfilling is evident, most acutely for 2 Th / 4 ms where 4 ms is frequently insufficient to reach the target. The narrowest-window method underfills most often except at 1000 ng and above.

So the favorable regime is real, sits at low load, and is where the interference problem lives anyway. The crossover is roughly 500 ng HeLa on that gradient and method set, and it moves with load, window width, injection time, and gradient. **Measure it per method rather than inheriting this number.**

On a single-ion-counting detector there is no such tension, because there is no meaningful floor to be pushed below. **This is the strongest argument for proving the method on the 8600 or on Astral MS2 rather than on an Exploris.**

Three further design consequences:

- **The floor must be a function of the method's resolving power**, never a constant. A threshold tuned at 120k will silently discard most of the output at 30k.

- **The useful ceiling on k is platform-specific.** The same nominal 25% stagger can be productive on a counting detector and recover little on an image-current Orbitrap in the AGC-limited regime. Do not carry a tuned *k* across detection technologies.

- **A feasibility test exists that requires no implementation work.** The Skyline document grid now reports Apex Total Ion Count Fragment and LC Peak Analyte Ion Count Fragment. Take existing staggered Orbitrap DIA data, compute per-precursor apex fragment ion counts, apply the transient-scaled floor, and count what fraction of precursors would retain enough fragments above threshold. That predicts the yield of demux before a line of solver code is written, and it should be done first.

Practical rule for the implementation: refuse to emit a demultiplexed bin whose recovered intensity corresponds to fewer than `minIonsPerBin` ions (default 3 for counting detectors; for image-current Orbitraps the transient-scaled charge floor above, whichever is larger). Report the fraction suppressed by this rule, and separately report the fraction of *input* measurements that were already censored, since those are unrecoverable and set the true ceiling on what demux can deliver.

The scanning TOF case should not be given the censoring treatment. Single-ion counting detection has no equivalent thermal floor, so a genuinely empty bin in ZT Scan or SONAR carries real information: it says the precursor is not in the bins that only that event covers. Set `censored = true` per file based on detection technology, not globally.

Weighting is applied by scaling rows of `A` and `y`. Since `y` varies per channel, the weighted `A` varies per channel, which breaks the shared-factorization trick. Two options:

- **Option A (adopted for v1):** quantize weights into a small number of bins (for example 8 levels per row), and precompute factorizations for the resulting weight patterns encountered. In practice a handful of patterns cover most channels.
- **Option B:** use unweighted least squares for the fast path and weighted only for channels that fail the fast-path test. Simpler, and given that the fast path is dominated by high-confidence single-bin solutions where weighting does not change the answer, probably sufficient. Measure both.

### 6.3 Three-tier solve

**Tier 0: support test (expected 50 to 70% of channels).**
Count rows of `y` above the noise floor. If the nonzero rows are exactly the set of events covering a single bin *j*, the answer is that bin, with `x_j` the weighted mean of those rows divided by the corresponding column of `A`. No linear algebra. This is the common case: a well-resolved precursor in the middle of the sweep.

**Tier 1: unconstrained solve plus feasibility test (expected 20 to 40%).**
Apply the precomputed pseudoinverse `A+` for that group geometry. One small dense multiply. If all components are nonnegative within tolerance, it is the NNLS solution and we are done.

**Tier 2: active-set NNLS (expected 5 to 15%).**
Lawson-Hanson, seeded from the Tier 1 solution's nonnegative support rather than from the empty set. Because solutions are sparse, this typically converges in one to three passivations. Cap iterations at N and record any channel that hits the cap.

For small N (say N <= 6, which covers 50% stagger and most 33% cases), replace the iterative path with **exhaustive active-set enumeration**: precompute the pseudoinverse of every column subset (2^N of them, at most 64 matrices of at most 13x6 floats, a few KB per geometry) and pick the lowest-residual feasible one. Fully branch-free and exact.

### 6.4 Determinism

Osprey guarantees bit-identical output across runs and platforms. The demux design supports that essentially for free, because of one structural property: **SIMD lanes are independent fragment channels, so there are no cross-lane reductions anywhere in the hot path.** Widening from AVX2 to AVX-512 changes how many channels are solved at once, never the arithmetic within a channel.

Additional rules:

- The `k`-term dot products inside the solve are accumulated in fixed index order. With M <= 13 there is no tree-reduction ambiguity to introduce.
- Factorizations of `A` are computed once per group geometry in `double`, in scalar code, then rounded to `float` for the hot path. Never compute them in vectorized or threaded code.
- Active-set tie-breaking (equal residuals, equal gradients) resolves to the lowest bin index. No exceptions.
- Channel ids are assigned by sorting cluster representative m/z ascending, never by hash iteration order. This is the same discipline as the existing window-sorting rule.
- Parallelism is over demux groups, and each group writes to its own output region, so thread count cannot affect results.
- Assert bitwise equality of `.spectra.bin` across `--threads 1` and `--threads N` in the regression suite.

---

## 6.5 Coupling across fragment channels

Sections 6.1 to 6.4 treat each fragment channel as an independent problem: one small NNLS per channel per time point. That is the wrong model, and correcting it is the largest available accuracy gain in this document.

### 6.5.1 Why independence is wrong

Fragment channels are not independent, because fragments have precursors. Every fragment of one peptide shares two things exactly:

- **The same precursor bin.** All of a peptide's fragments come from one precursor m/z.
- **The same elution profile.** They are the same molecules eluting at the same time.

Twenty peptides in a 10 Th window contribute perhaps 300 fragment channels but only twenty underlying components. Solving 300 independent problems discards a factor of fifteen in redundancy, and it discards precisely the redundancy needed to break the degeneracy of Section 3.

### 6.5.2 What the redundancy buys

Take the minimal staggered case: three bins, two windows covering `{0,1}` and `{1,2}`. `A` is 2×3 with rank 2, and its null vector is the alternating pattern `(1, −1, 1)`. For a single channel with `y = (a, b)`, every `x = (a−t, t, b−t)` with `t` in `[0, min(a,b)]` fits exactly. **Non-negativity does not select among them.** A fragment shared between a peptide in bin 0 and another in bin 2 is exactly this case, and it is common rather than exotic.

Coupling resolves it. Moving intensity into the middle bin would require a phantom peptide there whose fragment pattern and elution profile happen to match a combination of the two real ones. Across hundreds of channels and dozens of time points that is not possible without a large residual.

Simulated: three bins, two peptides in the outer bins with elution profile correlation 0.891 (deliberately similar), 15 fragments each, 5 channels shared between them.

| | Phantom middle-bin intensity | Shared-channel assignment error |
|---|---|---|
| Per-channel, per-timepoint, noiseless | 10.2% | 73.1% |
| Coupled across channels and RT, noiseless | **0.0%** | **0.0%** |
| Per-channel, 400 ions | 10.0% | 72.3% |
| Coupled, 400 ions | **0.0%** | **2.3%** |
| Per-channel, 100 ions | 10.2% | 74.0% |
| Coupled, 100 ions | **0.1%** | **5.6%** |

The per-channel solver misassigns roughly three quarters of the shared-channel intensity and cannot do better, because the information required is not present in a single channel. The coupled solve recovers the correct bin distributions essentially exactly, and degrades gracefully with ion count rather than failing.

**Shared fragments help rather than hurt**, which is the counterintuitive part. In the per-channel view a shared fragment is the worst case, sitting squarely in the null space. In the coupled view it is an additional constraint tying two components together, and the elution difference that distinguishes them is available even when the profiles are highly correlated.

### 6.5.3 Formulation

Decompose the block into components, each with a bin distribution, a fragment pattern, and an elution profile:

```
y_i(c, t)  =  sum_r  (A b_r)_i  ·  w_r(c)  ·  s_r(t)          b, w, s >= 0
```

Component *r* is one precursor: `b_r` its bin distribution (expected to concentrate on one bin), `w_r` its fragment intensity pattern, `s_r` its chromatogram. Fit by alternating nonnegative least squares. In the simulation the recovered `b_r` came out as `(0, 0, 1)`, `(0, 0, 1)`, `(0.998, 0.002, 0)` — the components found their bins without being told bins were sparse.

#### How the elution profile is determined

`s_r(t)` is unknown, and the natural worry is that it must therefore be assumed: a template shape, or a sweep over candidate EMG widths. **Neither is needed, and both would be liabilities.** `s_r(t)` is fit as a free non-negative vector, one value per time point, by exactly the same alternating least squares that fits `b_r` and `w_r`. Nothing about peak shape is assumed.

**Why it is identifiable.** The profile is shared across every channel belonging to that component. With C channels and T time points there are `2CT` measurements constraining `T` unknowns in `s_r` plus `C` in `w_r` plus 3 in `b_r`. The problem is overdetermined by orders of magnitude, and the profile is simply the consensus of many independent observations of the same eluting molecule.

More precisely, this is the uniqueness property of three-way decomposition. A two-way factorization is rotationally ambiguous, so an arbitrary shape can be traded against an arbitrary loading. The trilinear structure here, over (bin × channel × time), is essentially unique under mild conditions on the factors, and that uniqueness is what removes the need for a shape prior.

**Tested against shapes that are not EMG.** Profile recovery is the correlation between the fitted `s_r` and the truth, at 400 ions:

| True shapes | Profile correlation between the two components | Phantom middle bin | Profile recovery |
|---|---|---|---|
| EMG / EMG | 0.891 | 0.0% | 1.000 / 0.994 |
| Shouldered (unresolved second peak) / EMG | 0.866 | 0.0% | 1.000 / 0.998 |
| Wide / sharp (5x width difference) | 0.534 | 0.0% | 0.999 / 1.000 |
| Sharp / shouldered | 0.359 | 0.0% | 1.000 / 0.998 |

A parametric EMG fit would have been actively harmful on the shouldered case, forcing a unimodal shape onto a peak that is not. Real chromatography produces shoulders, variable tailing, and coelution; the non-parametric fit absorbs all of it.

**How close in retention time can two components be?** Sweeping the separation with identical shapes:

| ΔRT | Profile correlation | Phantom middle bin | Profile recovery |
|---|---|---|---|
| 1.6 | 0.690 | 0.1% | 1.000 / 0.977 |
| 1.0 | 0.868 | 0.1% | 1.000 / 0.995 |
| 0.6 | 0.950 | 0.1% | 0.999 / 0.994 |
| 0.3 | 0.987 | 0.0% | 1.000 / 0.997 |
| 0.15 | 0.997 | 0.0% | component matching becomes ambiguous |

Separation holds to a profile correlation of about 0.99, well past the point where the two chromatograms look alike by eye. Below that the components merge, which is the expected and correct behaviour for peptides that genuinely coelute (Section 6.5.3, failure mode).

**What smoothness is for.** The spline basis of Section 4.3 still applies to `s_r(t)`, but as a roughness penalty rather than a shape model. It suppresses fitting noise between measurements without dictating what the peak looks like. Knot spacing is set from measured peak widths per file, so components of different widths coexist in one basis. That is the whole extent of prior information used about elution.

Notes on making this work in practice:

- **Rank selection.** Too few components merges peptides; too many splits one across several. Start from the count of distinct elution profiles detectable in the block and allow a margin. Report the chosen rank.
- **Library-free by construction.** Grouping comes from elution-profile similarity in the raw data, never from a spectral library. This is required, not merely preferred: the cache must remain a pure function of the raw file (Section 9.1) or the shared `--cache-dir` guarantee is lost.
- **`b_r` concentration is a diagnostic, not a constraint.** Do not force each component onto a single bin. A component whose `b_r` refuses to concentrate is evidence of a real problem, either a genuinely coeluting pair or an under-determined block, and should be reported rather than suppressed.
- **Failure mode.** Two peptides that coelute exactly and share most fragments are not separable by this or any other method here. The coupled solve should merge them into one component and say so, rather than splitting them arbitrarily.

### 6.5.4 Cost, and what actually changes

**SIMD is not removed; its axis moves.** An earlier draft said the vectorization strategy "does not survive," which is wrong. What does not survive is *lanes-as-independent-channels*. Vectorization itself applies at least as well as before, and arguably better: the inner kernel becomes MTTKRP (matricized tensor times Khatri-Rao product), a dense regular contraction, in place of thousands of tiny active-set solves with data-dependent branching. Dense contractions are the easy case for both SIMD and cache blocking.

Each alternating least squares sweep is three MTTKRPs plus three R×R solves, where the R×R system is the Hadamard product of the other two modes' Gram matrices and is trivially small. Cost per sweep is `O(M·C·T·R)`.

**Measured**, on the same 2.1 GHz virtualized core as Section 7.4, 25 ALS sweeps per block:

| M | C | T | R | sec/block | GFLOP/s |
|---|---|---|---|---|---|
| 5 | 300 | 30 | 25 | 0.029 | 5.8 |
| 5 | 150 | 30 | 15 | 0.008 | 6.7 |
| 7 | 500 | 40 | 40 | 0.090 | 9.4 |
| 3 | 200 | 25 | 15 | 0.008 | 4.4 |

Scaled to a 60 min staggered Astral run (400-900 m/z, 2 Th bins, 1 s cycle, 5-bin precursor regions, RT blocks of 30 points at 2× overlap, so 50 × 240 = 12,000 blocks):

| Configuration | Single core | 16 cores |
|---|---|---|
| Per-channel tiered path (Section 7.4) | 1.9 s | — |
| Coupled, all channels | 317 s | 20 s |
| Coupled ALS restricted to 35% of channels | 64 s | 4.0 s |
| Coupled ALS restricted to 20% of channels | 45 s | 2.8 s |
| Anchored two-stage (see below) | comparable to per-channel | — |

**Where the factor comes from.** The per-channel path touches each measurement once: one small NNLS per (channel, cycle), a handful of arithmetic operations each. Coupled ALS touches each measurement `modes × sweeps × overlap` times, which at 3 mode updates, 25 sweeps, and 2× RT block overlap is **150 passes over the data**, and each pass does `R` multiply-adds per element rather than a handful. The cost ratio is that product, not anything mysterious, and every term in it is a tunable rather than a constant.

**Stating the ratio carefully.** Two different comparisons are easy to conflate:

| Comparison | Ratio |
|---|---|
| Coupled ALS versus per-channel **solve only** (317 s vs 0.6 s) | 528× |
| Coupled ALS versus per-channel **total, including channel merge and I/O** (317 s vs 1.9 s) | 167× |

An earlier draft quoted the second, which is the less meaningful of the two, since it compares a solve against a solve-plus-overhead. The arithmetic ratio is closer to 500×.

**The ratio is also the wrong figure of merit.** What matters is the fraction of a real cache build, where vendor file parsing dominates both:

| Vendor parse | Per-channel | Coupled, all channels, 16 cores | Coupled, selective, 16 cores |
|---|---|---|---|
| 120 s | 1.6% of build | 14.2% | 3.2% |
| 300 s | 0.6% | 6.2% | 1.3% |
| 600 s | 0.3% | 3.2% | 0.7% |

So coupling changes demultiplexing from negligible to noticeable, and with selective coupling to a few percent of build time. That is a real change in character but not a prohibitive one, and it parallelizes cleanly over blocks since they are independent by construction.

#### Anchored solving: use the easy channels rather than discarding them

An earlier draft proposed "selective coupling": drop the unambiguous channels from the block and factorize only the ambiguous ones. **That is backwards.** The unambiguous channels are exactly the ones that determine each component's bin and elution profile. A fragment unique to one peptide has support in only the windows covering that peptide's bin, so the per-channel solve already returns its bin uniquely, and the profile it traces is that peptide's chromatogram measured cleanly. Discarding them removes the anchors and leaves the factorization to infer from the hardest data only.

The right structure is two stages, not a smaller factorization:

**Stage 1 — anchor.** Run the per-channel tiered solve on everything. Classify each channel: if its recovered support concentrates on one bin across the RT block, it is unambiguous and already correct. Cluster the unambiguous channels by elution-profile similarity. Each cluster is a component, and it directly supplies that component's bin distribution `b_r` and its elution profile `s_r`, with no iteration at all.

**Stage 2 — project.** For each ambiguous channel, solve for the component amplitudes `w_r(c)` only, against fixed `b_r` and `s_r`. That is one small nonnegative least squares of size `(M·T) × R` per ambiguous channel. No alternating updates, no mode sweeps.

Measured on the shared-fragment simulation (30 channels, 5 of them shared between peptides in different bins):

| | Shared-channel error | Phantom middle bin |
|---|---|---|
| Per-channel only, noiseless | 73.1% | 10.2% |
| Anchored, noiseless | **0.0%** | **0.0%** |
| Per-channel only, 400 ions | 72.3% | 10.1% |
| Anchored, 400 ions | **2.5%** | **0.0%** |
| Per-channel only, 100 ions | 74.7% | 10.1% |
| Anchored, 100 ions | **6.4%** | **0.0%** |

**This matches full ALS to within a few percent at a small fraction of the cost.** The expensive part of ALS is iterating to discover the components; anchoring reads them off the easy channels instead. Cost is one small NNLS per ambiguous channel, in the same regime as the per-channel path rather than hundreds of times above it.

**When full ALS is still required.** A component with no unambiguous channels at all, meaning every one of its fragments is shared, cannot be anchored. Detect this as ambiguous channels whose residual against the anchored component set stays high, and fall back to full ALS for those blocks only. It should be uncommon, and the fallback cost then applies to a small minority of blocks rather than to the whole run.

#### Noise behaviour of the anchoring stage

Stage 1 makes two decisions from noisy data, and they fail very differently. Tested across a 100-fold range of ion counts, with a wide fragment dynamic range (weakest fragment 6% of strongest), 5 of 30 channels truly shared, six replicates per point:

| Ions at apex | Components found (true: 2) | Bad anchors | Shared-channel error | Phantom bin |
|---|---|---|---|---|
| 2000 | 2.0 | 0.00 | 1.7% | 0.0% |
| 500 | 4.0 | 0.00 | 3.6% | 0.0% |
| 200 | 13.7 | 0.00 | 6.6% | 0.0% |
| 100 | 19.7 | 0.00 | 10.0% | 0.0% |
| 50 | 24.2 | 0.00 | 14.7% | 0.0% |
| 20 | 25.0 | 0.00 | 22.5% | 0.0% |

**The classification decision is robust.** A "bad anchor" is a genuinely shared channel misclassified as unambiguous, which would inject a wrong bin and a wrong profile into a component. **Zero occurred at any ion count**, because the concentration test is evaluated on intensity summed over the whole RT block rather than per time point, so noise averages out. A truly shared channel carries substantial signal in windows covering both bins, and noise does not easily erase that.

**The clustering decision degrades, but benignly.** Profile clusters fragment as noise decorrelates them: 2 components at 2000 ions, 25 at 20 ions. Error grows smoothly rather than breaking, and no phantom intensity appears.

**Do not make the correlation threshold noise-adaptive.** This was the obvious fix and it is actively harmful. Lowering the threshold to accommodate noisy profiles merges components that are genuinely distinct: the two peptides in this simulation have profile correlation 0.891, so any threshold below that fuses them into one. Measured, an adaptive threshold that dropped to 0.80-0.93 collapsed to a single component and pushed shared-channel error to 30-45%, far worse than the fixed 0.98 threshold at every ion count.

**The asymmetry is the design rule: over-splitting is benign, merging is fatal.** An over-split component set contains near-duplicates, and Stage 2 simply distributes amplitude among them, since they span the same subspace. A merged set has lost the distinction the whole method exists to make, and no downstream step recovers it. **Keep the clustering threshold high and fixed.** Accept over-splitting.

**How much does over-splitting cost?** Against an oracle handed the true two components:

| Ions at apex | Anchored (fixed 0.98) | Oracle | Gap |
|---|---|---|---|
| 2000 | 1.7% | 0.9% | 0.8% |
| 200 | 6.6% | 2.8% | 3.8% |
| 50 | 14.7% | 6.1% | 8.6% |
| 20 | 22.5% | 9.0% | 13.5% |

The gap is real and widens at low ion counts, so component recovery is worth improving, but the correct direction is a better clustering criterion at high threshold rather than a looser one. Candidates worth testing: intensity-weighted profile estimation before clustering, and a post-hoc merge of near-duplicate components validated by residual rather than by correlation. Report the component count in the metrics JSON so over-splitting is visible; it also inflates R and therefore Stage 2 cost.

**Where the floor is.** At 20 ions at the apex, spread over a chromatographic peak and multiple fragments, per-channel ion counts are in the low single digits and the oracle itself is at 9% error. That is the counting-statistics limit, not an algorithmic one. It is also below the charge floor of any image-current analyzer (Section 6.2), so on those platforms the measurements would already be censored.

**float32 does not help here** and measured slightly slower (77 s versus 69 s on the same block set), because the contraction is not bandwidth-bound at these sizes and the float64 BLAS path is better tuned. Keep the coupled solve in double precision, which also removes a determinism hazard.

**What must be re-derived.** The determinism gates in Section 11.4 were written for a decomposition into independent per-channel lanes. Under coupling the guarantees still hold, and by the same argument — fixed update ordering within a block, deterministic tie-breaking to lowest index, blocks independent so thread count cannot matter — but they need restating against ALS rather than against NNLS lanes, and ALS convergence must be made bit-reproducible by fixing the iteration count rather than using a residual-based stopping rule.

### 6.5.5 The general pattern

Three sections now make the same argument along three different axes:

| Axis | Sequential approach | Joint approach | Section |
|---|---|---|---|
| m/z within a spectrum | Centroid, then demultiplex | Model peak shape and demultiplex together | 5.4d |
| Retention time | Interpolate, then demultiplex | Model the chromatogram and demultiplex together | 4.3 |
| Fragment channels | Solve each channel alone | Model precursor components across channels | 6.5 |

In every case the sequential version fabricates an intermediate the joint version never needs, and in every case the joint version is better conditioned because the peak model supplies constraints the demultiplexing lacks.

The fully coupled formulation joins all three: components over (precursor bin, fragment m/z profile, retention time), fitted to raw measurements at their acquired positions on both axes. That is the correct destination. It is also a substantial build, and each pairwise version captures most of the benefit of its axis, so the pairwise versions come first and the full coupling is gated against them.

---

## 7. Performance engineering

### 7.1 Layout

Structure of arrays, indexed `[event][channel]`, `float32` for intensities, `float64` retained only for m/z. This puts consecutive channels in consecutive lanes, which is exactly the axis we want to vectorize over.

Rationale for `float32`: the dynamic range of a single TOF or Orbitrap centroid is far below 24 bits of mantissa, memory bandwidth is the binding constraint, and it doubles lane count. m/z stays `float64` because 5 ppm at 1000 Th needs the precision.

### 7.2 Vectorization strategy

Do not reach for a general BLAS. At M x N of 13x19 the call overhead exceeds the arithmetic, and no GEMM kernel is tuned for that shape.

Instead, transpose the parallelism: hold the `A`-derived coefficients in registers, stream 8 or 16 channels at a time through the lanes, and run the entire solve lane-parallel with masking for divergent control flow.

- `System.Numerics.Vector<float>` for portable code, with `Vector256<float>` / `Vector512<float>` intrinsic paths in `System.Runtime.Intrinsics.X86` where it pays.
- `System.Numerics.Tensors.TensorPrimitives` for the bulk elementwise and reduction helpers.
- No native BLAS dependency. Keeping the build clean inside `pwiz_tools` is worth more than the last 20% of throughput.
- Tier 2 divergence is handled by predication: maintain a per-lane active-set bitmask in a `Vector256<int>`, iterate a fixed maximum of N passes, mask off converged lanes. Worst case is deterministic and bounded.

### 7.3 Allocation

Zero allocation in the inner loop. `ArrayPool<float>` for per-group scratch, `stackalloc` for the per-geometry coefficient blocks, buffers sized once per group and reused across cycles.

### 7.4 Cost estimate (measured)

The kernel was benchmarked directly rather than estimated: AVX2, 8 float lanes, tiered dispatch, projected-gradient active set as a cost proxy for Lawson-Hanson, on a single 2.1 GHz Xeon vCPU. Lanes are fragment channels, no cross-lane reductions.

**Measured per-solve cost**

| Geometry | Tier mix | Batching | ns/solve |
|---|---|---|---|
| Staggered, M=3 N=5 | 60/30/10 | unsorted | 9.12 |
| Staggered, M=3 N=5 | 60/30/10 | **tier-sorted** | **3.87** |
| ZT Scan, M=13 N=19 | 60/30/10 | unsorted | 99.30 |
| ZT Scan, M=13 N=19 | 60/30/10 | **tier-sorted** | **29.55** |
| Staggered, M=3 N=5 | all tier 2 | sorted | 14.94 |
| ZT Scan, M=13 N=19 | all tier 2, 19 iters | sorted | 501.90 |

**Tier-homogeneous batching is mandatory, not an optimization.** This is the one result that changes the design. A SIMD batch runs to its slowest lane, so with 8 lanes and a 10% tier 2 rate, 1 - 0.9^8 = 57% of batches contain a tier 2 channel and pay full tier 2 cost. The tiering in Section 6.3 therefore buys almost nothing unless channels are classified first and compacted into batches of uniform tier. Measured penalty for skipping it: **2.4x for staggered, 3.4x for ZT Scan.** The classification pass is cheap, since Tier 0 and Tier 1 assignment falls out of a support test and a sign test that must be computed anyway.

**End-to-end, single core**

Combining the measured kernel with workload arithmetic. Blocked stepping means solving a block of events for several bins at once and stepping by *k*, rather than a sliding group per bin.

| Run | Records | Peaks | Solves | Solve | Merge | I/O | Total |
|---|---|---|---|---|---|---|---|
| ZT Scan 8600, 30 min, sliding | 1.5 M | 77 M | 189 M | 5.6 s | 1.6 s | 0.3 s | **7.5 s** |
| ZT Scan 8600, 60 min, sliding | 3.1 M | 154 M | 378 M | 11.2 s | 3.2 s | 0.6 s | **15.0 s** |
| ZT Scan 8600, 30 min, blocked | 1.5 M | 77 M | 27 M | 0.8 s | 1.6 s | 0.3 s | **2.7 s** |
| ZT Scan 8600, 60 min, blocked | 3.1 M | 154 M | 54 M | 1.6 s | 3.2 s | 0.6 s | **5.4 s** |
| Staggered Astral, 30 min | 0.45 M | 68 M | 81 M | 0.3 s | 0.4 s | 0.3 s | **1.0 s** |
| Staggered Astral, 60 min | 0.90 M | 135 M | 162 M | 0.6 s | 0.8 s | 0.5 s | **1.9 s** |

Assumptions: 400-900 m/z; ZT Scan at 1.5 Th bins and 858 Hz with 50 centroids per binned record; staggered Astral at 2 Th effective bins, 1 s cycles, 150 centroids per record; group channel count from a *k*-event union at 35% (ZT Scan) or 60% (staggered) of the naive sum; merge at 3 ns per step; 2.5x write amplification at 8 GB/s.

**Conclusions.**

1. **Demux is seconds, not minutes.** Even the sliding-group ZT Scan case is 15 s single-threaded on a slow virtualized core, against minutes of vendor file parsing. Parallelized across groups and on faster cores with AVX-512, this drops well below the noise of cache construction.
2. **Blocked stepping is worth ~3x on ZT Scan** and costs only a larger `A`. Prefer it wherever conditioning permits.
3. **For ZT Scan, channel merging costs as much as or more than the solve.** In the blocked case merge is 3.2 s against 1.6 s of arithmetic. Section 5 is the unglamorous part of this document and it is also, on the fastest acquisition, the hot path. Optimize it accordingly.
4. **The worst case is bounded and still tolerable.** Forcing every ZT Scan channel through tier 2 at the full 19-iteration cap gives 502 ns/solve, 17x the mixed case: about 95 s for the 30 min sliding run. Pathological, but not a hang.

### 7.5 Sensitivity to spectral density

Centroids per spectrum is the dominant unknown in Section 7.4, and its effect is not a simple scale factor. Two coupled mechanisms pull in different directions.

**Solve count saturates.** Channels per group is the size of the *union* of centroid sets across the *k* events in the group, not their sum. In ZT Scan the bins within a group all transmit largely the same precursors, since the sweep window spans several bins, so the *k* events see nearly identical fragment sets and the union barely grows once the fragment space is populated. Across a 32-fold increase in centroids per spectrum, ZT Scan solve count rises only 5.5-fold.

**Per-solve cost rises.** Denser spectra put signal in more events per channel, shifting the tier mix away from Tier 0. Measured ns/solve against Tier 0 share (sorted batches):

| Tier 0 share | Staggered, ns | ZT Scan, ns |
|---|---|---|
| 0.80 | 2.18 | 14.03 |
| 0.60 | 3.06 | 26.50 |
| 0.40 | 4.47 | 43.15 |
| 0.20 | 6.65 | 64.22 |
| 0.05 | 8.96 | 103.46 |

**Merge and I/O do not saturate.** Both scale with raw peak count, so they grow linearly without limit.

Combining all three:

**ZT Scan 8600, 30 min, blocked stepping**

| Centroids/spectrum | Peaks | Solves | ns/solve | Solve | Merge | I/O | Total |
|---|---|---|---|---|---|---|---|
| 25 | 39 M | 36 M | 16.6 | 0.6 s | 0.8 s | 0.1 s | **1.5 s** |
| 50 | 77 M | 65 M | 19.0 | 1.2 s | 1.6 s | 0.3 s | **3.2 s** |
| 100 | 154 M | 112 M | 22.3 | 2.5 s | 3.2 s | 0.6 s | **6.3 s** |
| 200 | 309 M | 164 M | 27.3 | 4.5 s | 6.5 s | 1.2 s | **12.1 s** |
| 400 | 618 M | 195 M | 36.2 | 7.1 s | 13.0 s | 2.3 s | **22.4 s** |
| 800 | 1236 M | 199 M | 50.4 | 10.0 s | 25.9 s | 4.6 s | **40.6 s** |

**Staggered Astral, 60 min**

| Centroids/spectrum | Peaks | Solves | ns/solve | Solve | Merge | I/O | Total |
|---|---|---|---|---|---|---|---|
| 25 | 22 M | 22 M | 2.2 | 0.0 s | 0.1 s | 0.1 s | **0.3 s** |
| 50 | 45 M | 45 M | 2.3 | 0.1 s | 0.3 s | 0.2 s | **0.5 s** |
| 100 | 90 M | 88 M | 2.4 | 0.2 s | 0.5 s | 0.3 s | **1.1 s** |
| 200 | 180 M | 173 M | 2.6 | 0.5 s | 1.1 s | 0.7 s | **2.2 s** |
| 400 | 360 M | 331 M | 2.9 | 1.0 s | 2.2 s | 1.4 s | **4.5 s** |
| 800 | 720 M | 605 M | 3.5 | 2.1 s | 4.3 s | 2.7 s | **9.1 s** |

**What this means for the design.**

1. **The headline conclusion survives the whole plausible range.** A 32-fold uncertainty in spectral density moves the 30 min ZT Scan run from 1.5 s to 41 s single core. Still small against vendor file parsing, at every density.

2. **The optimization target moves.** At low density the solve dominates on ZT Scan; above roughly 100 centroids per spectrum, merge and I/O dominate and further solver tuning is wasted effort. Profile before optimizing, and expect the answer to differ between platforms.

3. **Density is a one-line measurement on existing data**, so do not carry these assumptions into Phase 2. Histogram `defaultArrayLength` over msLevel 2 spectra in any converted file, or emit it from the reader directly. It should be the first number in the metrics JSON.

**Remaining uncertainties, in order:** the shared-fragment fraction between events in a group, which sets where solve count saturates; the true Tier 2 share; and the merge cost per step, taken here as 3 ns. All are metrics JSON outputs, so replace these tables with measured values as soon as Phase 2 produces any.

## 8. Memory

### 8.1 The shape of the problem

Representative full-run peak volumes:

| | MS2 records | Peaks/record | Raw peak bytes |
|---|---|---|---|
| ZT Scan, 30 min, 400 bins, 3,900 cycles | 1.56 M | ~50 | ~0.9 GB |
| Astral 50% stagger, 60 min, 600 windows, 2,400 cycles | 1.44 M | ~150 | ~2.6 GB |

Holding an entire run in memory and demultiplexing it in place would fit in 32 GB but leaves no headroom and scales badly to longer gradients.

### 8.2 Streaming design

Demultiplex during the first pass, in acquisition order, using a **cycle ring buffer**.

- Stepped staggered: a demux group spans `cyclesInBlock` cycles, default 3, plus the *k*-cycle stagger period. A ring buffer of `2k + cyclesInBlock` cycles is sufficient. One cycle of all windows for the Astral case is about 600 x 150 x 12 B = 1.1 MB, so a 7-cycle ring is under 10 MB.
- Comb (parallel isolation): the buffer must span every acquisition whose comb touches the block, which is set by the comb span and the sub-cycle ordering rather than by a constant. Compute it from the acquisition schedule at startup. Still small in absolute terms, since it is a modest multiple of the stepped case.
- Scanning: a group is contained within one cycle. Ring buffer of 3 cycles for safety.

As each cycle leaves the ring, its groups are complete and can be solved. Solved records are routed into per-window output accumulators.

### 8.3 The real memory consumer is the output

`.spectra.bin` v4 requires the MS2 body grouped by isolation window, so demultiplexed records must be buffered until their window is complete, which is the end of the run.

Output size is **not** *k* times the input. Each input peak is distributed among bins, and after thresholding most peaks resolve to one or two bins. Expect 1.5x to 2.5x the input peak count, with the record count going up by roughly *k* but the mean peaks per record going down correspondingly.

Budget: 2 to 7 GB of output buffer for the cases above. That fits, but bound it explicitly:

- The output buffer cap is internal, not a user setting. Per the numbers above it sits well below what library loading and scoring already consume, so exposing it would invite tuning of the one thing in this subsystem that is not close to a constraint.
- Per-window accumulators spill to per-window temp files when the budget is exceeded, then the writer concatenates them in window order. Since the v4 body is already window-grouped, spill files map one-to-one onto output runs and the merge is a sequential copy with no sorting.
- Thread count is capped so that `threads * perGroupFootprint + outputBuffer <= budget`. Per-group footprint is small (10 to 40 MB), so this constraint almost never binds.

### 8.4 Sparsification

Apply a threshold to demultiplexed intensities before writing:
- Absolute floor expressed **in ions**, via `N = y * IT / alpha` (Section 6.2). Default 2 ions. An intensity-unit floor would need retuning for every instrument and would not transfer between an Astral file and an Orbitrap file.
There is deliberately no relative threshold. An earlier draft proposed dropping bins below 1% of the channel's total recovered intensity, which was a heuristic stand-in from before the charge floor in Section 6.2 gave a physically grounded absolute floor. A relative rule would suppress genuine minor components in crowded bin groups precisely where interference removal is the point, and its cutoff would be arbitrary. The ion floor is derived from `alpha` and the transient length, so it needs no tuning.

Record the total intensity dropped as a diagnostic. If it exceeds a few percent, the thresholds are too aggressive or the kernel is misfitted.

---

## 9. Cache format and integration

### 9.1 `.spectra.bin` v5

The v4 layout is already the right shape. MS2 records are grouped by isolation window with an acquisition-order index and an EOF footer, and each record carries `iso_center`, `iso_lower`, `iso_upper` individually. Demultiplexed records are simply records with narrower offsets. **No structural change to the body is required.**

Header additions for v5:

| Field | Type | Purpose |
|---|---|---|
| `demux_flag` | uint8 | 0 = passthrough, 1 = demultiplexed |
| `acquisition_kind` | uint8 | stepped-staggered / scanning-quad / neither |
| `overlap_factor_k` | uint8 | 0 when not applicable |
| `demux_param_hash` | uint64 | hash of the full effective parameter set |
| `kernel_model_len` | uint32 | length of the serialized kernel block |
| `kernel_model` | bytes | fitted transfer-function coefficients, for audit and reuse |

Cache validation gains one rule alongside the existing source size and mtime check: **reject if `demux_param_hash` differs from the current effective parameters.** This preserves the settings-independence property that makes a shared `--cache-dir` safe, by making the demux parameters part of the cache identity rather than pretending they do not exist.

Serializing the fitted kernel is worth the bytes. It makes a cache auditable after the fact and lets a later run reuse a calibration rather than refitting.

### 9.1b Where demux sits relative to calibration

The cache is written **before** any search-dependent calibration, and must stay that way, since that is what makes it settings-independent and shareable across analyses. The question is whether demux breaks that, since demux needs calibrations of its own.

**Sort the calibrations by whether they need identifications.**

| Calibration | Needs PSMs? | Affects demux? |
|---|---|---|
| Q1 transfer function / sweep kernel (Section 2.4) | No, fit from surviving unfragmented precursor ions | Yes, it *is* `A` |
| Q1 bin-center offset | No, same probes | Yes, sets precursor axis truth |
| Per-event fragment m/z offsets (Section 5.1) | No, differential between events in a group | Yes, controls linking |
| Global fragment mass recalibration | Yes | **No, see below** |
| LOESS RT calibration | Yes | No, RT is stored as acquired |

Everything demux needs is derivable from raw data alone. There is no circular dependency on the search.

**Global mass recalibration does not require redoing demux.** Channel linking is differential: it compares centroids between events, so a common systematic offset shifts every event equally and cancels in the gap test. Only the per-event differences matter, and those are handled locally in Section 5.1. Global recalibration is applied downstream at scoring time, as it is today, and never written back into the cache. **Corollary: do not write recalibrated m/z into `.spectra.bin`.** Doing so would both destroy settings-independence and create exactly the rewrite dependency this section exists to avoid.

### 9.1b-i Which calibrations persist, and in what form

Two different things get called "cached" here, and conflating them is an easy implementation error.

| Calibration | Persisted? | In what form |
|---|---|---|
| Q1 kernel, bin-center offset | Yes | Parameters in the v5 header; **effect baked into the demuxed intensities** |
| Per-event fragment m/z offsets | Yes | Effect baked into the pooled representative m/z; fitted values reported in metrics |
| Tolerance model `a`, `b` | Yes | Reported in metrics; effect baked into which centroids were linked |
| Global fragment mass recalibration | **No** | Refit in memory per analysis, applied at scoring |
| LOESS RT calibration | **No** | Refit in memory per analysis |

**The demux calibrations are not "applied and stored" as corrections. They are consumed.** The kernel defines `A`, and `A` determines the demultiplexed intensities, so the effect is inseparable from the output. The serialized `kernel_model` block exists for audit and for reuse via `--demux-kernel`, not because anything re-applies it on read. There is no path back to the pre-demux values from `.demux.spectra.bin`, which is precisely why `.spectra.bin` is retained (Section 9.1c).

**The search-dependent calibrations stay in memory, as today.** They depend on the library and search settings, they are cheap relative to the search itself, and caching them would reintroduce the invalidation problem that the two-artifact split exists to avoid.

**One interaction worth flagging.** The per-event m/z offset correction in Section 5.1 is differential: it removes scatter *between* events without moving the absolute scale, since the pooled representative is a weighted mean over the corrected events. Downstream global recalibration therefore still sees the same systematic error and works unchanged. What does change is the *width* of the fragment mass error distribution feeding that fit, which should tighten by roughly sqrt(*k*) per Section 5.4. That is a benefit, but anything downstream that has tuned thresholds against the historical width should be checked rather than assumed safe.

### 9.1c Two artifacts, not one

The remaining problem is practical. Fitting the kernel needs probe observations spread across the gradient, which are not available until the raw file has been read, but demux must happen while reading it. Reading the vendor file twice is the obvious fix and the wrong one: per Section 7.5 the parse dominates everything else by orders of magnitude.

**Write a passthrough cache first, then demultiplex cache to cache.**

1. **Pass 1, vendor read.** Parse once. Write `.spectra.bin` in passthrough form, exactly as today. Accumulate kernel probe observations and per-event offset statistics along the way; these are a few hundred probes times a few numbers, so the memory cost is nil.
2. **Fit.** Kernel, bin-center offset, tolerance model parameters `a` and `b`. Fast, no file access.
3. **Pass 2, cache to cache.** Read `.spectra.bin`, demultiplex, write `.demux.spectra.bin`. This reads our own window-grouped binary rather than the vendor format, which Section 7.5 puts at 0.3 to 4.6 s of I/O rather than minutes of parsing. The v4 layout is already grouped by isolation window, which is exactly the access pattern demux wants.

This is better than a version bump on a single file for four reasons:

- **It resolves the cache-identity tension raised with Brendan.** `.spectra.bin` stays a pure function of the raw file, settings-independent and safe in a shared `--cache-dir`. `.demux.spectra.bin` carries `demux_param_hash` and is invalidated on parameter change. The two concerns stop fighting.
- **Demux becomes independently re-runnable.** Change a parameter, redo seconds of work instead of re-parsing the raw file. This matters enormously during development and for the Section 11 gates.
- **Gate G2.11 becomes structural rather than a code path.** Passthrough equivalence is not something to test, it is what pass 1 produces by construction.
- **It isolates failure.** A demux bug cannot corrupt the raw cache, and a diagnostic run can compare the two files directly.

Cost: transient disk for two files, and one extra write plus read of our own format. Cheap against the alternative.

**When the kernel is supplied via `--demux-kernel`,** passes 1 and 2 can be fused, since nothing needs fitting. Treat that as an optimization, not the default, and gate it on producing byte-identical output to the two-pass path.

### 9.2 Scan numbers

Open question requiring a decision. A demultiplexed group produces *k* records that all derive from one acquired scan.

- **Option A:** keep the parent scan number on all *k* records. Records remain traceable to real acquired scans, which matters for blib `RetentionTimes` output and for anything Skyline round-trips. Requires that nothing in Osprey assumes `(scan_number)` uniqueness among MS2 records. Window grouping plus `iso_center` already disambiguates.
- **Option B:** synthesize `parent * k + subIndex`. Guarantees uniqueness, breaks the mapping back to the raw file.

Preference is Option A. Audit `SpectrumFileReader`, `SpectraWindowIndex`, `BlibWriter`, and peak boundary output for uniqueness assumptions before committing.

### 9.3 Detection and control

**Governing principle: anything determinable from the data is determined from the data, and is not an option.**

This is not only about interface clutter. Every knob that changes numeric output must enter `demux_param_hash`, which fragments the cache and undermines the shared `--cache-dir` story from Section 9.1. A tuning parameter therefore carries a real cost, and the ones below did not earn it.

**Derived, never user-set:**

| Quantity | Determined from |
|---|---|
| Acquisition kind (stepped, scanning, neither) | First-cycle window layout plus vendor metadata |
| Overlap factor *k* | Window boundary structure. The data is the only place this exists. If detection is ambiguous, that is an error to report, not a default to override. Allowing a forced *k* would let a user demand more specificity than the acquisition contains, and the solver would dutifully manufacture it. |
| Bin boundaries | Sorted union of observed window boundaries (Section 2.2) |
| Block cycles | Cycle time versus median chromatographic peak width, both measurable |
| Edge width and kernel shape | Fitted (Section 2.4) |
| Ion floor and censoring threshold | `alpha` and transient length (Section 6.2) |
| Output buffer cap and spill point | Available memory |

**Complete CLI surface:**

```
--demux {auto|off}            default auto. Kill switch only.
--demux-kernel <path>         load a previously fitted transfer function
--demux-metrics <path>        write the metrics JSON sidecar
```

Plus `--alpha`, which is an Osprey-wide setting rather than a demux one, since it governs all ion-count reporting.

Justification for the three that survive. `--demux off` is required by gates G2.11 and G2.12 and enables honest A/B comparison, so it earns its place. `--demux-kernel` covers the case where a run has too few probe precursors to fit its own transfer function and a calibration from a richer run on the same instrument must be carried over; the kernel file contents are hashed into `demux_param_hash` so cache identity is preserved. `--demux-metrics` is an output path and changes no numbers.

Internal constants remain adjustable in code for development. They are not promoted to flags because a flag is a promise of support.

Print the inferred scheme, *k*, bin width distribution, and fitted kernel summary at startup. Silent auto-detection of something this consequential is a support burden.

---

## 10. Diagnostics

Emit to the Osprey diagnostics log, per file:

1. **Scheme detection:** inferred kind, *k*, bin width distribution, count of windows that did not fit the inferred pattern.
2. **Kernel fit quality (scanning only):** number of probe precursors, residual of the parametric fit, fitted lag in Th, integrated profile width versus nominal sweep width.
3. **Tier shares:** fraction of channels resolved at Tier 0, 1, 2, plus count of Tier 2 channels that hit the iteration cap.
4. **Ringing metric:** for each group, the mean amplitude of the period-*k* alternating component of the recovered bin intensities, normalized to total intensity. This is the direct signature of under-regularization and should be near zero. A rise in this metric is the first thing to check when demux makes results worse.
5. **Mass balance:** total intensity in versus total intensity recovered, plus intensity dropped by thresholding. Systematic loss indicates a kernel that is too wide; systematic gain indicates one that is too narrow.
5b. **Ion budget:** the `alpha` in use and its provenance (metadata table, user override, or infusion calibration), median ions per input event, and the distribution of ions per recovered bin. A demultiplexed bin carrying two or three ions is not a measurement, and the fraction of output falling in that regime is the honest measure of how far the demux can be pushed for a given acquisition.
6. **Interpolation stress (stepped only):** median cycle time divided by median chromatographic FWHM.
7. **Timing and peak memory** per phase.

---

## 11. Validation and acceptance gates

Every gate below is designed to be run and judged without human interpretation, so that a phase can be handed to an implementation session with an unambiguous definition of done. Two conventions make that possible.

### 11.0 Machine-readable metrics contract

**The tool emits its own evidence.** Add a `--demux-metrics <path>` flag that writes a JSON sidecar during cache build, and an `osprey demux-validate <spectra.bin> [--truth <path>]` subcommand that re-reads a cache and emits the same schema. No gate should require ad hoc analysis scripts, because those drift from the code and cannot be trusted as a regression signal.

```json
{
  "schema_version": 1,
  "source": { "file": "...", "sha256": "...", "acquisition_kind": "stepped-staggered",
              "k": 2, "detector": "image-current", "alpha": 10.6,
              "median_transient_ms": 32.0, "charge_floor": 19.1 },
  "structure": { "cache_version": 5, "n_ms2_in": 1440000, "n_ms2_out": 2810000,
                 "index_consistent": true, "windows_contiguous": true,
                 "bounds_nested_in_parent": true, "negative_intensities": 0 },
  "solver": { "tier0_frac": 0.61, "tier1_frac": 0.29, "tier2_frac": 0.10,
              "tier2_iter_cap_hits": 143, "median_solve_ns": 41 },
  "recovery": { "mass_balance_ratio": 0.997, "intensity_dropped_frac": 0.008,
                "ringing_metric_median": 0.004, "ringing_metric_p99": 0.031,
                "input_censored_frac": 0.22, "output_below_floor_frac": 0.11 },
  "kernel": { "fitted": true, "n_probes": 412, "fit_r2": 0.991,
              "lag_th": 0.42, "width_vs_nominal": 1.03 },
  "resources": { "wall_s": 118.4, "demux_wall_s": 19.2, "peak_rss_gb": 6.1,
                 "threads": 16 },
  "determinism": { "output_sha256": "..." }
}
```

**Gate IDs are stable.** Each gate has an ID (G1.1, G2.3, and so on) that can be cited in a task handoff, a commit message, or a CI job name. A phase is complete when all of its gates pass and no earlier gate has regressed.

Gates are one of three kinds: **hard** (build fails), **soft** (warn, record, require sign-off), and **report-only** (no threshold yet, establish the baseline). Every threshold below is a starting proposal to be recalibrated once real numbers exist. Recalibrating a threshold is fine; silently removing a gate is not.

---

### 11.1 Phase 0: feasibility, no implementation required

Runs entirely on existing data using the Skyline ion-count metrics.

| ID | Metric | Threshold | Kind |
|---|---|---|---|
| G0.1 | Fraction of currently quantified precursors retaining >= 4 fragments above the transient-scaled charge floor at apex | report | report-only |
| G0.2 | Same, restricted to the bottom quartile of precursor abundance | report | report-only |
| G0.3 | Fraction of MS2 measurements already censored at input | report | report-only |

**Decision rule, not a pass/fail:** if G0.1 falls below roughly 25% on the target platform, demux cannot deliver there regardless of solver quality, and the effort belongs on a counting detector instead.

**A back-of-envelope that suggests this gate will bite hard.** Hsu et al. Figure 5A reports modal LC peak peptide ion counts on the Orbitrap Astral, summed over transitions and over all scans within the peak boundaries: 25 to 189 ions for 2 Th / 4 ms across 200 to 2000 ng, 63 to 253 for 3 Th / 6 ms, and 110 to 293 for 4 Th / 8 ms. With a 6 s expected peak width and cycle times near 0.7 s, that is roughly 8 to 9 scans across the peak, spread over on the order of 6 quantified transitions. A modal peptide at 100 LC peak ions therefore carries roughly **2 ions per transition per scan**, perhaps 4 to 6 at the apex.

On a counting detector with a floor near 1 ion, that is a measurement. Against an Orbitrap MS2 charge floor of 10 to 20 (Section 6.2 item 5), the modal peptide does not clear the floor on a single fragment, before demux is even considered. Only the upper tail of the abundance distribution would survive.

If that arithmetic holds against real per-transition numbers, it is the strongest argument in this document for the 8600 and Astral MS2 as the platforms to prove the method on, and it also means G0.1 should be computed per transition rather than per peptide. Do this calculation properly before Phase 1: the Skyline metrics needed already exist.

---

### 11.2 Phase 1: solver correctness against exact ground truth

Synthetic re-multiplexing (Section 11.7) provides truth. All gates are hard.

| ID | Test | Threshold |
|---|---|---|
| G1.1 | Noiseless boxcar round-trip, k=2: max relative error per nonzero bin | < 1e-5 (float32) |
| G1.2 | Support recovery, noiseless: F1 over which bins are nonzero | = 1.0 |
| G1.3 | NNLS agreement with a reference implementation over 10^5 random small systems (M in 2..13, N in 3..19, mixed conditioning) | max abs difference < 1e-6 |
| G1.4 | Nonnegativity: count of negative components in any solution | 0 |
| G1.5 | Poisson-noised round-trip at 100 ions/bin: median absolute relative error | < 0.10 |
| G1.6 | Same at 20 ions/bin | < 0.30 |
| G1.7 | Ringing metric, single isolated precursor, noiseless | < 0.01 |
| G1.8 | Kernel misspecification sweep: median error at +/-10% kernel width error, relative to matched-kernel error | < 2.0x |
| G1.9 | Censored-row handling: recovery error on synthetic data with rows censored below a known threshold, versus treating them as exact zeros | strictly better |

G1.3 is the highest-value test in the whole document. Property-based comparison against an independent NNLS implementation over randomized systems catches active-set bugs that no curated example will.

G1.5 and G1.6 should also be reported as a curve of error versus ions per bin. That curve, not a single number, is the honest characterization of the solver and it feeds directly into the `minIonsPerBin` default.

---

### 11.3 Phase 2: cache integrity, invariants, and memory

Structural gates, all hard, all checkable by `osprey demux-validate` on any produced cache.

| ID | Test | Threshold |
|---|---|---|
| G2.1 | v5 header round-trip: every field written is read back identically | exact |
| G2.2 | Index consistency: index entry count equals `n_ms2`, every offset resolves to a valid record, footer offsets correct | exact |
| G2.3 | Window grouping: all records sharing an iso-center key are physically contiguous | true |
| G2.4 | Bounds nesting: every demuxed record's `[iso_lower, iso_upper]` lies within some parent acquisition window | 100% |
| G2.5 | Tiling: demuxed bins within a group cover the parent range with no gaps and no overlap beyond `1e-6` Th | true |
| G2.6 | Nonnegativity in persisted data | 0 negatives |
| G2.7 | Mass balance: total recovered intensity divided by total input intensity | 0.95 to 1.02 |
| G2.8 | Cache invalidation on `demux_param_hash` change | rejected |
| G2.9 | Cache invalidation on source size or mtime change | rejected |
| G2.10 | Cache hit on identical params and source | accepted, no rebuild |
| G2.11 | **Passthrough equivalence:** with `--demux off`, MS2 record content is byte-identical to the v4 body for the same input | exact |
| G2.12 | **Null-acquisition no-op:** running with `--demux auto` on non-overlapping standard DIA produces passthrough output | identical to G2.11 |
| G2.13 | **Idempotence:** attempting to demux an already-demuxed cache is detected and refused | error, not silent double-demux |
| G2.13b | Fused single-pass path with `--demux-kernel` supplied versus the two-pass path | byte-identical |
| G2.13c | `.spectra.bin` produced by pass 1 is bit-identical whether or not demux is subsequently run | exact |
| G2.14 | Peak RSS on the largest test file | <= configured budget |
| G2.15 | Spill path: force an internal cap below the natural output size; result is identical to the unspilled run | byte-identical |
| G2.16 | The set of inputs feeding `demux_param_hash` equals the documented option list in Section 9.3, asserted in code | exact |

G2.11 and G2.12 are the regression guards that matter most in daily development. They catch the case where demux code paths perturb data they should never touch.

G2.15 is worth the effort because the spill path is exercised rarely and will otherwise rot.

---

### 11.4 Phase 3: determinism and performance

| ID | Test | Threshold | Kind |
|---|---|---|---|
| G3.1 | `--threads 1` versus `--threads N` output SHA-256 | identical | hard |
| G3.2 | Scalar versus AVX2 versus AVX-512 paths (forced by env var) | identical | hard |
| G3.3 | Repeat run, same machine, same params | identical | hard |
| G3.4 | Phase 3 vectorized output versus Phase 1 scalar reference on the same input | identical | hard |
| G3.5 | Demux wall time as a fraction of total cache build | < 0.20 | soft |
| G3.6 | Gen0 collections per million solves | < 10 | soft |
| G3.7 | Tier shares (tier0, tier1, tier2) | report | report-only |
| G3.8 | Tier 2 iteration-cap hits as a fraction of tier 2 solves | < 1e-4 | soft |
| G3.9 | **Tier-homogeneous batching:** measured throughput versus a build with classification-and-compaction disabled | >= 2x speedup | hard |
| G3.10 | Measured ns/solve at each geometry, reported to the metrics JSON | within 2x of Section 7.4 | soft |

G3.4 is the reason Phase 1 should be kept as a compiled reference implementation rather than deleted once the fast path works. It is the only test that proves the optimization changed nothing.

---

### 11.5 Phase 4 and 5: generalization and kernel fitting

| ID | Test | Threshold |
|---|---|---|
| G4.1 | All Phase 1 gates re-run at k = 3 and k = 4 | pass |
| G4.2 | Ringing metric versus k on synthetic data | report, expect monotone increase |
| G4.3 | Variable-width staggered schedule: boundary-union bins have no zero-width or negative-width members | 0 |
| G4.4 | Variable-width: condition number of `A` per group | report, flag groups above threshold |
| G4.5 | Comb acquisition: synthetic round-trip at the published 4-sub-window geometry, all Phase 1 gates | pass |
| G4.6 | Comb conditioning: computed `min|H(w)|` is strictly positive, and the reported condition number matches a direct SVD of `A` | agree to 1e-6 |
| G4.7 | Comb versus contiguous at matched isolated width and matched ion counts: recovery error on synthetic data | comb strictly better |
| G4.8 | Comb ranking utility: for a set of candidate offset sets, predicted ranking by `min|H(w)|` matches observed ranking by synthetic recovery error | Spearman > 0.9 |
| G4.9 | MSX: synthetic round-trip with a random incidence pattern, all Phase 1 gates | pass |
| G4.10 | **Unequal fill times:** synthetic data generated with per-window accumulation times varying over at least 4x, solved with the time-weighted `A` versus the 0/1 `A` | time-weighted strictly better; 0/1 shows systematic bias |
| G4.11 | Equal-fill reduction: with all `tau_ij` equal, the time-weighted solve reproduces the 0/1 solve | identical to 1e-6 |
| G4.12 | `sigma_min(A)` reported per file agrees with a direct SVD, for staggered, comb, and MSX geometries | 1e-6 |
| G4.13 | Per-bin cumulative accumulation time emitted, and bins below a determinability threshold are flagged | reported |
| G4.14 | **Two-bin mixture recovery** on synthetic data, swept over mixture ratio and ion count, at k=2 staggered, comb, and MSX geometries | report the curve; MSX best, k=2 worst |
| G4.15 | Tier 0 gated on the censoring threshold rather than exact zero | mixtures with a censored row are not misrouted to Tier 0 |
| G4.16 | Isotope-envelope split: fraction of a known precursor's fragment intensity recovered outside its monoisotopic bin | matches predicted isotope distribution within 20% |
| G4.17 | MSX schedule periodicity verified across the run; incidence matrix constant | true, or fail with a clear diagnostic |
| G4.18 | Exactly one factorization built for a fixed-pattern MSX file | count == 1 |
| G4.19 | Fused interpolate-and-solve operator versus sequential interpolation then solve, on synthetic data with RT skew | fused strictly better |
| G4.20 | Super-cycle pattern rotation at P = 2, 3, 4: `sigma_min` improvement versus added RT skew penalty | report the trade curve |
| G4.21 | Effective per-bin sampling interval reported; equals cycle period divided by overlap factor | matches the acquisition schedule |
| G4.22 | **Joint temporal fit versus interpolate-then-solve**, swept over points per FWHM and ion count, with a coeluting interference present in one window only | joint better on apex and peak-boundary accuracy; area comparable |
| G4.23 | Apex retention time quantization | joint fit resolves below the cycle period; interpolation path does not |
| G4.24 | Knot spacing sensitivity: recovered peak shape versus knots per FWHM | minimum located; adaptive spacing beats fixed across a gradient |
| G4.25 | Warning emitted below 2 points per FWHM per bin after interleave | fires |
| G4.26 | **Coupled versus per-channel solving** on synthetic data with fragments shared between peptides in different bins | coupled strictly better; phantom middle-bin intensity near zero |
| G4.27 | Recovered component bin distributions concentrate without being constrained to | reported; non-concentrating components flagged |
| G4.28 | Rank selection sensitivity: recovery error versus assumed component count | minimum located; over-ranking degrades gracefully |
| G4.28b | Profile recovery against non-parametric truth shapes (shouldered, bimodal, extreme width contrast) | correlation > 0.98; no shape model invoked |
| G4.28c | Component separation versus elution profile correlation | separable to correlation ~0.99; merge behaviour correct beyond |
| G4.29 | Exactly coeluting, fragment-sharing peptide pair | merged into one component and reported, not split arbitrarily |
| G4.30 | Determinism of the coupled solve across block orderings and thread counts | byte-identical |
| G4.31 | ALS stopping rule is a fixed sweep count, not residual-based | asserted in code |
| G4.32 | **Anchored two-stage versus full ALS** on shared-fragment synthetic data | agree within a few percent at a fraction of the cost |
| G4.32b | Bad-anchor rate: truly shared channels misclassified as unambiguous, swept over ion count | 0 |
| G4.32d | Clustering threshold is fixed and high; no noise-adaptive lowering | asserted in code |
| G4.32e | Anchored versus oracle-component error, swept over ion count | gap reported; drives clustering improvements |
| G4.32c | Blocks with no anchorable component detected and routed to full ALS | correctly identified; fraction reported |
| G4.33 | Coupled solve wall time as a fraction of total cache build | report; flag above 0.5 |
| G5.1 | Kernel parametric fit R-squared, ZT Scan | > 0.98 |
| G5.2 | Fitted integrated profile width versus nominal sweep width | within 10% |
| G5.3 | Fitted lag: positive and smoothly varying in m/z | monotone within noise |
| G5.4 | Predicted versus observed Q1 profile residual on held-out probe precursors | report |
| G5.5 | Bin center m/z accuracy: known precursors appear at the expected bin | within 1 bin |

G5.5 is a precondition, not a result. If bin centers are wrong, every downstream number is meaningless, so run it first and fail loudly.

---

### 11.6 Cross-cutting quantitative gates

These are the gates that decide whether demux was worth doing. Run on three-proteome mixes and on the matrix-matched EV dilution series.

| ID | Metric | Threshold | Kind |
|---|---|---|---|
| G6.1 | **Primary:** median absolute deviation of log2 ratio from expected, yeast and E. coli, on the precursor set shared between demux and no-demux | improves | hard |
| G6.2 | Ratio compression: slope of observed versus expected log2 ratio | closer to 1 | hard |
| G6.3 | Median CV of shared precursors | does not degrade by more than 1 absolute point | hard |
| G6.4 | Precursor and protein ID counts | do not drop by more than 2% | soft |
| G6.5 | **FDR calibration:** entrapment-estimated FDR versus reported q-value | within 20% relative | hard |
| G6.6 | Human background precursors: recovered intensity in the absent-organism channels | decreases | soft |
| G6.7 | Agreement with narrow-window or PRM acquisition of the same sample on a shared peptide set | improves | soft |

**G6.5 deserves emphasis.** Demux turns one acquired spectrum into *k* records that are not statistically independent, since they share the same underlying measurement and noise. That is a plausible route to inflated apparent evidence and miscalibrated FDR. **An ID count increase with no accompanying improvement in G6.1 should be treated as a failure signal, not a success.** Osprey's existing entrapment support makes this directly measurable, and it should gate every quantitative claim.

---

### 11.7 Test data generation

Three sources, in increasing order of realism and decreasing order of ground-truth quality.

**Synthetic re-multiplexing.** Take narrow-window or PRM data, numerically combine it into wide staggered windows or a simulated sweep using a chosen kernel, then demultiplex and compare to the original. Truth is exact. Parameters to sweep: k, kernel shape, kernel misspecification, ion counts per bin (via Poisson resampling), censoring threshold, and RT skew between cycles. `pwiz/analysis/demux/DemuxTestData` is a precedent for the pattern. This generator is a deliverable of Phase 1, not an afterthought, because every later gate depends on it.

**Matched acquisitions.** Same sample, same LC, acquired both ways: staggered versus direct narrow windows on the Orbitrap platform, and ZT Scan versus Zeno SWATH on the 8600. Truth is the narrow acquisition. This is the honest test of whether demux recovers what a narrower window would have measured directly.

**Benchmark mixtures.** Three-proteome mixes and the EV matrix-matched dilution series. No per-measurement truth, but known ratios, which is what G6.1 and G6.2 need.

Keep a small, fast synthetic set in the regression suite (seconds), and a larger real-data set behind a separate command for release gating (minutes to hours).

---

### 11.8 Comparison against existing implementations

| ID | Test | Expectation |
|---|---|---|
| G7.1 | Osprey inline demux versus `msconvert --filter "demultiplex optimization=overlap_only"` on the same staggered Orbitrap file, searched identically | systematic differences must be explained, not averaged away |
| G7.2 | Demuxed ZT Scan versus DIA-NN `--scanning-swath` Q1-profile scoring on the same file | different approach, not a reference truth; compare, do not gate |

G7.1 is a soft gate deliberately. Agreement with pwiz would be reassuring, but pwiz uses boxcar masks, no censored-row handling, and unweighted or proximity-weighted least squares, so exact agreement is not expected and would arguably indicate that the improvements in this spec are not doing anything.
## 12. Dependencies and open questions

1. **Sweep geometry from pwiz.** Requested; not blocking, because Section 2.4 recovers the kernel empirically. If it lands, it improves the initial fit and validates the lag.
2. **SONAR data access.** The Waters reader path needs the same investigation the SCIEX path received: confirm that quadrupole bin centers survive conversion and that bin ordering within a cycle is recoverable. Structurally identical to ZT Scan, so the algorithm carries over unchanged, but the reader work is separate.
3. **Bin center accuracy for ZT Scan.** Everything depends on the reported bin center m/z being correct. Validate against known precursors before trusting any demux output.
4. **Scan number uniqueness audit** (Section 9.2).
4b. **Per-sub-window accumulation times.** Three of the four schemes in this document need a piece of per-event timing or geometry metadata that vendor readers currently discard or may never have exposed: sweep start and stop for ZT Scan (question 1), separately recorded sub-windows for parallel isolation (question 5a), and per-precursor accumulation times for MSX co-isolation. Determine for each whether the instrument records it, whether the vendor API exposes it, and whether the reader surfaces it. Ask all three together rather than piecemeal, since they are the same request in three costumes: **do not collapse a per-bin quantity into a per-scan scalar.** Where the answer is no, Section 2.0's equal-fill fallback applies and must be flagged in the metrics JSON.
5a. **Comb detection.** Auto-detection currently keys on contiguous overlap structure. It must also recognize a comb: build the boundary union, count overlaps per unit per cycle, and treat non-contiguity as a normal case rather than a parse error. Confirm the vendor file records each sub-window of a parallel isolation event separately, since if the sub-windows collapse into a single reported range the comb structure is unrecoverable and the same request made of ProteoWizard for sweep geometry applies here too.
5b. **Variable-width staggered Astral schedules.** Confirm the boundary-union bin construction in Section 2.2 behaves on real variable-window staggered methods, which may produce bins of very unequal width and correspondingly unequal conditioning.
6. **Source of `alpha` per file.** A built-in table keyed on instrument model from the raw metadata covers the common cases, but prototypes and reconfigured instruments will not match. Provide `--alpha` and document the Glu-fib or Ultramark infusion procedure as the way to measure it. Decide whether a wrong `alpha` should be a hard failure or a warning, given that it cancels from relative weighting and affects only the ion-denominated thresholds.
7. **Modernize the charge-floor constants.** The scaling law and the 5 to 6 charge figure at 0.76 s are now anchored (Makarov and Denisov 2009), but they were measured on an LTQ Orbitrap XL with a standard-field analyzer and 2009 electronics. Two corrections are needed for current instruments: the high-field S/N gain (roughly 1.4x) and any preamplifier improvement since. Measure `N_0` directly on a current Exploris or Astral-Orbitrap by the same individual-ion quantization method, or bound it empirically from the lowest reported centroid intensities as a function of resolving power. Also confirm that the S/N = 1 reporting cutoff still holds in current firmware.
8. **The useful ceiling on k is platform-specific, not scheme-specific.** Determine it empirically per detection technology rather than assuming a single answer. The prediction from Section 6.2 item 5 is that scanning TOF and Astral tolerate higher k than image-current Orbitrap at matched nominal overlap, and that 25% stagger on an Exploris or Lumos may recover nothing usable while the same scheme on an Astral does. Falsify or confirm this before generalizing past k = 2.

---

## 12b. Citation and constant verification status

This document mixes claims taken from primary sources with numbers reconstructed from summaries. The distinction matters, because a number quoted from memory can be wrong in ways that look exactly like a number quoted from a paper. Verify anything marked unverified before the spec is circulated or any of it reaches a manuscript.

| Claim | Source | Status |
|---|---|---|
| Overlapping-window demux, NNLS formulation | Amodei et al., *JASMS* 2019, 30(4), 669-684 | Verified |
| MSX scheme and fivefold selectivity gain | Egertson et al., *Nat Methods* 2013, 10(8), 744-746 | Verified |
| Parallel isolation multiplexing scheme and figures | EP 4 535 399 A1 | Verified from the published application |
| Orbitrap noise band of 5 to 6 charges at 0.76 s, 4 charges at 1.5 s; noise falls as sqrt(acquisition time); peaks at S/N <= 1 not reported | Makarov and Denisov, *JASMS* 2009, 20, 1486-1495 | Verified from the paper |
| Ion calibration framework, `y = alpha * N / IT` | Hsu et al., *J. Proteome Res.* 2025, 24(11), 5742-5754 | Citation verified |
| `alpha` values, per analyzer (Astral 1.31 and 1.53; ion trap 0.97 to 1.09; Orbitrap 9.40 to 15.44) | Hsu et al. 2025, Table 1 | Verified against the paper |
| Non-Poisson variance term essentially zero, R-squared > 0.998 in all cases | Hsu et al. 2025, Table 1 footnote | Verified against the paper |
| Underfilling at 200 ng, AGC target of 20,000 ions reached at 500 ng for 3 Th / 6 ms and 4 Th / 8 ms | Hsu et al. 2025, Results | Verified against the paper |
| Modal LC peak peptide ion counts of 25 to 383 across methods and loads | Hsu et al. 2025, Figure 5A | Verified against the paper |
| Orbitrap noise stratification: detector noise plus censoring at low signal, counting noise at intermediate | OrbiSIMS noise-structure work, *Nat Commun* | **Citation not recorded.** Locate it or drop the supporting reference and rest the argument on Makarov and Denisov alone. |
| Extrapolated charge floors at DIA MS2 transients (7 to 27 charges) | Derived here from the 2009 scaling law | Derived, not measured. See open question 7. |
| ZT Scan parameters: 5 Da at 750 Da/s, 10 Da faster setting, 858 Hz and 4000 Da/s on the 8600, effective deconvolved Q1 windows | Vendor technical notes and product literature | Single-source, from vendor marketing material. Confirm against the instrument and method files. |

Two general rules for anyone extending this document. First, a citation with an author surname and a year is a claim like any other and should be checked, not inherited. Second, when a number is reconstructed rather than read, say so at the point of use rather than only in a table like this one.

Worth recording how this table earned its keep. The three Hsu et al. rows were flagged unverified because they had been reconstructed from a summary rather than read from the paper, and the same summary had produced a wrong first author. On checking against the paper, all three numeric claims were correct. But the check was still worth making, and not only for the reassurance: reading Table 1 properly revealed that `alpha` is a property of the analyzer rather than the instrument, which is a structural error the numbers alone would not have exposed.

---

## 13. Phasing and handoff

Each phase below states its deliverables and the exact gate set that defines done. A phase may be handed to an implementation session with nothing more than its row here plus Section 11.

| Phase | Deliverables | Done when | Also must not regress |
|---|---|---|---|
| **0** | Skyline ion-count feasibility analysis. No code. | G0.1 to G0.3 reported and the decision rule applied | n/a |
| **1** | Forward model, scalar NNLS solver, synthetic data generator, stepped staggered k=2 | G1.1 to G1.9 pass | n/a |
| **2** | Cache v5, streaming, ring buffer, output buffering and spill, `demux-validate`, metrics JSON | G2.1 to G2.15 pass; G6.1 to G6.5 reported on three-proteome | G1.* |
| **3** | SIMD solver, three-tier dispatch, precomputed factorizations, parallelism | G3.1 to G3.8 pass | G1.*, G2.* |
| **4** | k=3, k=4, variable-width staggered schedules, comb parallel isolation, MSX random co-isolation, time-weighted `A` | G4.1 to G4.13 pass | G1.*, G2.*, G3.* |
| **5** | Kernel calibration, ZT Scan support, 8600 validation | G5.1 to G5.5 pass; G6.1 to G6.3 improve on matched 8600 acquisitions | all prior |
| **6** | SONAR, contingent on Waters reader work | G5.* re-run on SONAR data | all prior |

Phases 1 through 3 deliver value on data already in hand. Phase 5 is the 8600 objective and depends on nothing in phases 4 or 6, so it can run in parallel with Phase 4 if there are two pairs of hands.

**Handoff conventions for implementation sessions.**

1. **The gate set is the specification of done.** A phase is not complete because the code appears to work. It is complete when `osprey demux-validate` and the regression suite emit passing values for every gate in the row, and the metrics JSON is committed alongside.
2. **Never delete a gate to make it pass.** Recalibrating a proposed threshold against real data is expected and welcome; record the old value, the new value, and the evidence in the commit. Removing a gate requires the same justification as removing a test.
3. **Report-only metrics still must be emitted.** Their purpose is to establish the baseline that later phases are compared against, so a missing value is a failure even though it has no threshold.
4. **Phase 1's scalar solver is a permanent artifact,** retained and compiled, because G3.4 compares against it. Do not replace it with the fast path.
5. **When a gate fails, the first question is whether the gate is measuring the right thing.** Several thresholds here are guesses. A failing G1.6 might mean the solver is wrong, or it might mean 20 ions per bin is simply below what any solver can do, which is itself a publishable result and belongs in Section 6.2 rather than in a bug report.