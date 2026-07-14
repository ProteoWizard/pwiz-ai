# TODO: Osprey — make peak_sharpness a scale-free shape feature

## Objective

Redesign `peak_sharpness` so it measures peak SHAPE independently of peak
INTENSITY, instead of being an intensity-magnitude feature wearing a shape
feature's name.

## Background

`peak_sharpness` is the mean of the left and right edge slopes on the reference
XIC: `(apexIntensity - edgeIntensity) / dt`. That is an ABSOLUTE slope
(intensity per minute), so it scales ~linearly with peak intensity — a 2x more
intense peak of the same shape has ~2x steeper slopes. It therefore carries the
same heavy tail as `peak_apex` and `peak_area`, and it demonstrably participated
in the Percolator intensity hijack (a lone high-intensity DIA interference
standardized to z ~= 190 on this feature alone).

The fix that shipped in pwiz#4412 / maccoss/osprey#53 conditions it with
`log10(max(x, 0) + 1)`, which compresses the tail and stops the hijack. That is
a conditioning change, not a redesign: the feature is still a function of
intensity, just a saturating one.

## The actual redesign

A scale-free sharpness would normalize the slope by the apex and stay linear:

```
sharpness = ((apex - leftEdge) / dtLeft + (apex - rightEdge) / dtRight) / 2 / apex
```

which is dimensionally 1/minute and invariant to a uniform intensity rescale, so
a sharp weak peak and a sharp strong peak get the same value. The model then
gets peak SHAPE from this feature and peak INTENSITY from `peak_apex` /
`peak_area`, instead of three correlated intensity features.

## Why it was not done in the hijack fix

The hijack was a production incident (a whole SEA-AD run collapsing to zero IDs
at 1:1 entrapment); the log conditioning is the minimal, parity-preserving change
that fixes it. A feature redesign changes the discovery set and needs its own
entrapment validation, so it is deliberately separate work.

## Tasks

- [ ] Implement `slope / apex` sharpness in C# (`PeakShapeCalculators.cs`) and
      Rust (`pipeline.rs`), keeping the two bit-identical.
- [ ] Decide what to do at `apex == 0` (all-zero XIC) — 0.0 sentinel, matching
      the current invalid-peak convention.
- [ ] Decide whether the new feature REPLACES `peak_sharpness` or is added
      alongside it. Replacing keeps the PIN vector at 21 features; adding grows
      it and changes the parquet schema on both sides.
- [ ] Re-bless the C# regression golden and re-run
      `Compare-EndToEnd-Crossimpl` on Stellar + Astral.
- [ ] **Entrapment validation is the gate, not parity**: run the FDRBench
      entrapment oracle (see ai/docs/osprey-development-guide.md) and confirm the
      accepted set does not gain entrapment hits. A redesign that moves the
      discovery set is exactly the case the oracle exists for.
- [ ] Check whether the log conditioning should then be REMOVED from sharpness:
      a scale-free feature has no heavy intensity tail, so conditioning it would
      be compressing a quantity that no longer needs it.

## Context

- Referenced from the `PeakSharpnessCalc` class doc in
  `pwiz_tools/Osprey/Osprey.Scoring/PeakShapeCalculators.cs`.
- The hijack fix and its validation: pwiz#4412, maccoss/osprey#53, and the
  v26.7.0 release notes ("Scoring and FDR").
- Coordinate with [[TODO-osprey_intensity_batch_normalization]] -- both are
  "condition the intensity-scale PIN features so the linear SVM sees the right
  signal"; a scale-free sharpness plus a normalized magnitude is the cleaner
  end state.
- Skyline analog: `MQuestShapeCalc` / shape features assessed at linear scale.
