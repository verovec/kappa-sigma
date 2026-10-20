# StackKit / Transient (and Trail)

The cross-frame transient mask (card 0081): satellite and aircraft trails, cosmic rays and hot
pixels removed from a channel's REGISTERED frames before the stack. It ports the legacy
`internal/transient` (`MaskCrossFrameValidated`, `MaskCrossFrameStreamed`, `budget.go`) and the
parts of `internal/trail` they use (`Trail/`). No recorded oracle exercises it (every 0044 case
ran with `TrailMaskK: 0`), so it is pinned by the legacy table tests, translated.

## The passes (`TrailMask`, per frame)

A frame is `frame[channel][pixel]`. The context is built once from the witnesses (the whole
sequence in memory, or the streamed basis): per-pixel median and 1.4826·MAD planes, each
witness's residual (most positive channel over the median, kept signed) and its sky noise.

1. **Blanket:** every pixel above median + k·σ takes the median (cosmic rays, hot pixels, a
   trail's bright core). Faint real signal is consistent across frames and never flagged.
2. **Lines:** `TrailSegmentDetector` finds up to four straight streaks on the frame's own
   residual (taken before the blanket). Each candidate is validated window by window along its
   corridor (`TrailCorridor`, 64-step windows): lit in this frame (mean ≥ k/2·sky over ≥ 32
   non-zero pixels, ≥ 24 lit pixels in all) and lit in under 30% of the witnesses (median over the
   lit windows) — walking noise lights the same windows in many frames and is rejected. Accepted
   runs (lit windows ±1) are painted from the median.
3. **Recurring corridors** (`RecurringCorridor`): a track several satellites reused is too faint
   per frame and absent from the median, but sums in the coverage-aware mean residual. Each frame
   repairs the windows it lights, from the median, or from the local sky where ≥ 45% of the basis
   lights the window (a contaminated median).
4. **Geostationary:** streaks present in the median itself are painted from the local sky in
   every frame (`TrailSwath.paintLocalBackground`: median of 1.5–3 widths off the swath plus
   matching noise).

Under five frames, or k ≤ 0, nothing runs. Zero-fill (Siril's registration border) is excluded
from the window means; a witness reading below −3σ over a window has no data there.

## Memory (`TrailMaskBudget`)

The in-memory pass holds every frame plus a residual each. While 3·n whole frames (every plane)
fit the budget it runs in memory; otherwise `maskStreamed` keeps budget / (2·frame) − 6 evenly
spaced basis frames (within [16, 48] and ≤ n) and masks every frame one at a time. A basis that
covers every frame reproduces the in-memory pass bit for bit (pinned). The budget is half the
physical memory, or `ASTRO_TRAIL_MASK_MEM_GB`. The seam noise pass uses the same budget
(W·H·4·10 bytes over it: skipped, with a warning).

## Departures from the legacy engine

- The local-sky fill draws from `SeededGaussian` (SplitMix64 + Box–Muller), not Go's
  `math/rand`: no oracle pins that stream, only the fill's statistics (tested).
- The saturated-core repair stays `Preprocess/SaturationRepair` (exact and sparse); it runs first
  on the same frames, so the plateau never reaches the median planes, as `satCeil` did.
- Not ported: the unvalidated `MaskSequence` and its per-frame fallback, and `MaskCrossFrame`
  alone (the legacy pipeline used neither; the blanket pass is pass 1 here), `trail.MaskFrame`.
- Hot medians sort through `vDSP.sort` (same order statistics, fast in debug builds too).

## How to extend

- The pipeline entry is `ChannelStacker.maskRegistered` → `Preprocess/ChannelTrailMask`
  (in-memory vs streamed, write-back, the legacy note). k is `PreprocessSettings.trailMaskK`
  (deepsky and nebula 3.0; 0 is off).
- A new pass goes in `TrailMask.maskFrame` so both modes run it, with a test that the full-basis
  streamed pass still equals the in-memory one.
- Test frames: `Tests/StackKitTests/Transient/TrailMaskFrames` (the legacy 300 × 300 sequences).
