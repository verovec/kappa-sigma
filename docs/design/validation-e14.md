# Validation E14 — the app's preprocessing on real targets (card 0058)

Measured on 2026-10-22 on the PO's Mac (Siril 1.4.4, release build, the machine shared with
other workers' test runs — timings are upper bounds). The harness is
`Tests/AstroStackAppTests/LiveValidationE14Tests.swift` (`swift test -c release --filter
LiveValidationE14`): the window model as the Stacking stage drives it — import, the user's
overrides, Run with the target's mode — then a JSON report per target set beside the legacy run
the PO validated:

| Target | Captures | Mode | Override | Legacy run |
|---|---|---|---|---|
| M 31 BB + DB | `M31-DB` + `M31-BB` | deepsky | the night of 2026-09-22 marked dual-band | #78 `runs/M_31/20261018_191749` |
| IC 1848 | `IC1848` | nebula | — | #79 `runs/IC_1848/20261018_221220` |

## Frames

| Target · lane | Lights in | Stacked (app) | Stacked (legacy) |
|---|---|---|---|
| M 31 · RGB (BB, 3 groups) | 84 | 77 (76 and 78 in two earlier runs) | 76 |
| M 31 · RGB-dualband | 36 | 34 | 34 |
| IC 1848 · RGB (3 groups) | 111 | 95 | 95 |

Same selection as the legacy runs. The ±2 between two app runs is Siril's star matching on the
same frames (the 0066 live test already allows it); nothing in the app chooses differently.

## Masters and bundle

- Sizes match: masters 6248 × 4176, bundle layers (after the combine's coverage trim) 5967 × 3763
  for M 31 — the legacy `rgb_base` / `syn_Ha` / `syn_OIII` sizes.
- **Absolute levels are not comparable as is.** Both engines stack lights with Siril's
  `-output_norm`, which rescales each master by its own min/max: one hot pixel or saturated star
  sets the scale, so medians differ by arbitrary factors between any two runs (app vs legacy:
  M 31 RGB 0.0071 vs 0.0132, DB 0.0130 vs 0.0528, IC 1848 0.0853 vs 0.00046). The legacy
  `rgb_base.fits` is also after its background extraction, the app's bundle before it.
- Pixel parity: see « Parity after the affine map » below.
- The bundle's Hα / [OIII] are synthesized from the dual-band lane as in the legacy run (0081).

## Timings

| Step | M 31 app | M 31 #78 | IC 1848 app | IC 1848 #79 |
|---|---|---|---|---|
| calibration masters | 16 s | 26 s | 9 s | 18 s |
| grading + stacking RGB | 514 s | 489 s | 740 s | 535 s |
| grading + stacking RGB-dualband | 152 s | 185 s | — | — |
| align + combine + bundle | 12 s | 11 s + finishing | 5 s | 10 s + finishing |
| **preprocessing total** | **695–729 s** (3 runs) | ~711 s (829 s with finishing) | **754–822 s** (2 runs) | ~563 s (1869 s with finishing) |

The legacy totals include finishing steps the app does in the Studio (background extraction,
colour calibration, GraXpert denoise 1172 s for #79, StarNet, GIMP). Stacking is within the
noise of a shared machine for M 31; IC 1848's 740 s ran while other workers' suites loaded the
CPU (load average 30–60) — to re-measure on an idle machine before reading it as a regression.

## Disk

Peak scratch (`$TMPDIR/AstroStack/Work/run_*`, measured at every step boundary): **80.6 GB** for
M 31 (120 lights, 0.67 GB per light) and **106 GB** for IC 1848 (111 lights, 0.95 GB per light —
three groups calibrated and registered at once). Removed when the run ends (0057). Nothing warns
before a run that the disk cannot hold it → card 0098.

## Calibration

Every master the run used is in the journal as warnings the user sees (R2): masters rebuilt from
this run's frames when the library's were built from other frames, the dark defect maps, and a
2-frame dark pool flagged (« outlier rejection needs at least 3 darks »). Per-night calibration
coverage is the Données matrix of 0078 — no new card.

## Found on the way

- **A project saved inside the captures.** `captures/IC1848/` holds `test-build.astrostack` (a
  run of 21/10, three stack FITS) and `test-kappa.astrostack`. Importing the folder scans into the
  package, reads its stacks as OBJECT-less lights, and the run is refused as « mixed objects
  ("", "IC 1848") ». The app lets a project be saved under `captures/` (R7) and the scan does not
  skip packages → card 0101. The packages were left in place: the PO's data, the PO's call.

## Parity after the affine map

Both masters are rescaled by Siril's `-output_norm`, so the app's master is fitted to the
legacy one per plane (`ours ≈ a·legacy + b`, least squares on every 7th pixel) and the residual is
read in units of the app master's own noise (MADN): 0 = identical, ≈ 1.4 = two independent stacks
of the same sky at the same depth.

| Master | a | b | correlation | residual / noise |
|---|---|---|---|---|
| M 31 RGB (R, G, B) | 0.960 · 0.961 · 0.961 | −0.0056 | 0.985 · 0.987 · 0.984 | 0.40 · 0.39 · 0.40 |
| M 31 RGB-dualband (R, G, B) | 1.053 · 1.069 · 1.051 | −0.043 | 0.999 · 0.999 · 0.999 | 0.51 · 0.49 · 0.52 |
| IC 1848 RGB (R, G, B) | 0.897 · 0.919 · 0.918 | +0.019 | 0.967 · 0.974 · 0.975 | 0.38 · 0.53 · 0.60 |

Reading: the same image as the validated runs, not a byte copy. The residual (≈ 0.4–0.5 of
the noise) is what one or two frames more or less (77 vs 76 here; Siril's star matching) and
Siril's registration resampling give; nothing structured (correlation ≥ 0.985). Byte identity
holds where it is claimed — against the recorded oracle with the same selection and scripts
(`PreprocessM31LiveTests`, mean |Δ| ≤ 1e-3). The runs of this report: M 31 696 s / 80.4 GB peak
(77 RGB stacked), IC 1848 822 s / 105.9 GB peak (95 stacked). IC 1848 correlates a little lower
(0.97): a faint, field-filling nebula leaves less structure above the noise to correlate on.

## Follow-up cards (registered after 0058, each depends on it)

- 0097 Pause and resume a preprocessing run at a channel boundary.
- 0098 Scratch budget — estimate before a run, refuse without room, sweep leftovers.
- 0099 Drizzle — Siril 1.4 drizzle stacking as an advanced, explicit knob.
- 0100 Add a night — an explicit full re-stack (PO decision: no calibrated-night cache).
- 0101 Captures stay read-only — no project saved there, the scan skips packages.

## PO decisions (2026-10-22)

1. Comparison signed off (« ok »): E15 may rely on the bundle.
2. 0100: **full re-stack in v1** (« restack all »), no calibrated-night cache.
3. The two test packages in `captures/IC1848/` deleted with the PO's consent; the 189 capture
   frames untouched.
