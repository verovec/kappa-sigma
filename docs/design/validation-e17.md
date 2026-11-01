# E17 / card 0062 — batch-tool measurements (Siril 1.4.4, GraXpert 3.0.2)

Measured 2026-10-21 on an Apple M5 Pro (18 logical cores, 48 GB RAM), macOS 27.0.1 (26A434). **Other heavy jobs were
running on the machine at the same time, so every wall time is an upper bound.** Times come from `/usr/bin/time -p`
around the whole CLI call, so they include process start and FITS load/save. Each command was capped at 20 min with a
`perl alarm` wrapper (macOS has no `timeout`). Tools ran one at a time.

- **Siril 1.4.4** (`/Applications/Siril.app/Contents/MacOS/siril-cli`, aarch64, "Copyright 2012-2026 team free-astro"),
  run as `siril-cli -d <work> -s <script.ssf>` with scripts that start with `requires 1.4.0`. It used 18 logical
  processors and ran on the CPU only.
- **GraXpert 3.0.2 "Umbriel"** (`/Applications/GraXpert.app/Contents/MacOS/GraXpert -cli -cmd …`), ONNX Runtime with
  `CoreMLExecutionProvider` + `CPUExecutionProvider`.
- **Inputs** (copied to scratch, FITS float32, normalised 0–1):
  - `m31_crop.fits`: `~/Documents/astro/fixtures/finish/crop/rgb_base.fits`, 1024×768×3. Its header has WCS (TAN-SIP),
    FOCALLEN=249 and XPIXSZ=3.76 (ZWO ASI2600MC Air = Sony IMX571). It also carries an ICC HDU, which Siril skips.
  - `m31_full.fits`: M31 run #78 `rgb_base.fits`, 5967×3763×3, same header keywords. I also copied `syn_Ha.fits`
    (5967×3763, 1 plane), but no process below needed it.
  - `ic1848_full.fits`: IC 1848 run `20261018_221220/rgb_base.fits`, 6248×4176×3. **Its header has no WCS, no
    FOCALLEN/XPIXSZ and no RA/DEC** (only `PROGRAM='Siril 1.4.4'`, `STACKCNT=3`, `HISTORY RGB composition`).
  - Files in the IC 1848 run: `rgb_base.fits`, `master_RGB.fits` (+ `_noise.png`, `_preview.png`), `syn_Ha.fits`,
    `syn_OIII.fits`, `linear/{base.tif, prep.json, rgb_base_bg.fits(+.note,.sig), rgb_base_denoised.fits(+.sig)}`, plus
    `final*.png/.tif/.xcf`, `IC1848_v9style_doux*.png`, `coverage_RGB.png`, `run.json`, `stages.json`, `_astrostack.ssf`.
    `prep.json` notes: "palette hoo: narrowband channel mapping (SPCC + SCNR skipped)", "colour denoise applied
    (GraXpert AI)", "combined background extracted (GraXpert + RBF residual pass)". The M31 run also has
    `linear/rgb_base_spcc.fits.json` = `"PCC photometric color calibration applied (SPCC unavailable: solve error)"`, so
    `rgb_base` is already colour-calibrated and background-extracted.
- **Metrics.** "Box MAD" = 1.4826·MAD of the green channel in a 64×64 region of the crop with no detected star
  (x 960–1023, FITS rows 0–63), in normalised units (×65535 in brackets). "bgnoise" = Siril `bgnoise`, in ADU16.
  "FWHM" = median of (FWHMx+FWHMy)/2 from `findstar -layer=1`, on stars matched within 1.5 px between before and after.
  "Ring" = for the 10 brightest unsaturated stars: min(annulus r 2.5–7 px) − median(annulus r 10–14 px), in units of
  the local background MAD. A positive value means no dark ring; a value far below 0 means a dark ring. The before
  values range from +0.5 to +8.3σ.
- **Crop baseline (no processing).** 529 stars, matched median FWHM 2.155 px (Siril's own median 2.32 px). Scale
  3.12″/px (from findstar, 8.70″ / 2.79 px). bgnoise R/G/B 1.973/1.516/1.400. Box MAD (G) 1.679e-5 (1.100).
  Image min 0.01312, 0 px < 0.
- **Full-frame M31 baseline.** bgnoise R/G/B 1.663/1.302/1.214.

## Deconvolution (Siril; GraXpert 3.0.2 has none)

All Siril runs used the PSF from `makepsf stars -sym` (32 suitably bright, non-saturated stars on the crop, 638 on the
full frame) unless the Flags column says otherwise.

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `rl` | M31 crop | `rl` (defaults: 10 iters, gradient descent, step 0.0005) | 2.01 s | no (CPU) | ok | FWHM 2.155→2.160 px (+0.2 %); ring +7.8→+7.6σ (none); bgnoise G 1.516→1.507. **Visually a no-op.** |
| Siril `rl` | M31 crop | `rl -iters=30 -tv` | 3.06 s | no | ok | FWHM +0.0 %; no ring; no-op |
| Siril `rl` | M31 crop | `rl -iters=50 -tv -stop=0.0002` | 1.14 s | no | ok | "Richardson-Lucy halted early by the stopping criterion after iteration 1"; FWHM +0.5 % |
| Siril `rl` | M31 crop | `rl -iters=20 -gdstep=0.002 -tv` | 1.02 s | no | ok | FWHM −1.9 %; ring: mostly none, but one star at −27.2σ; 0 px < 0 |
| Siril `rl` | M31 crop | `rl -iters=50 -gdstep=0.005 -tv` | 1.89 s | no | ok | FWHM −11.3 % (2.150→1.907); **ringing** −68σ to −332σ on all 10 stars; 1083 px < (median − 5σ); stars 529→452 |
| Siril `rl` | M31 crop | `rl -iters=3 -mul` | 0.41 s | no | ok | FWHM −9.5 % (2.150→1.945); **ringing** −50σ to −99σ (top 5 stars); bgnoise G 1.516→2.069 |
| Siril `rl` | M31 crop | `rl -iters=10 -mul` | 1.37 s | no | ok | FWHM −21.4 % (2.145→1.685); **ringing** −68σ to −232σ on all 10; peak ×2–3; stars 529→308; bgnoise G 1.516→2.969 |
| Siril `rl` | M31 crop | `rl -iters=10 -mul -fh` | 0.76 s | no | ok | Identical to `-mul` to 3 digits (−21.4 %, same ring values) |
| Siril `rl` | M31 crop | `rl -iters=30 -mul -tv` | 1.34 s | no | ok | FWHM −28.5 %; **ringing** −110σ to −426σ; 4 px < 0; stars 529→92 |
| Siril `rl` | M31 crop | `makepsf blind` + `rl` | 2.96 s | no | ok | Blind PSF: 3 iterations, lambda 0.001; FWHM −0.0 %; no-op |
| Siril `rl` | M31 crop | `makepsf manual -moffat -fwhm=2.3 -beta=4.5` + `rl` | 0.68 s | no | ok | FWHM +0.0 %; no-op |
| Siril `sb` | M31 crop | `sb` (1 iter, alpha 3000) | 1.00 s | no | ok | FWHM −10.8 %; **severe ringing** −98σ to −7012σ; 452 px < 0; min −1.52; stars 529→218 |
| Siril `sb` | M31 crop | `sb -alpha=1000` | 0.52 s | no | ok | FWHM **+10.7 %**; **severe ringing** −65σ to −5533σ; 320 px < 0 |
| Siril `wiener` | M31 crop | `wiener` | 0.87 s | no | ok | Stars 529→4 detected; **severe ringing** −155σ to −1129σ; 885 px < 0; bgnoise G 1.516→9.530 |
| Siril `wiener` | M31 crop | `wiener -alpha=0.1` | 0.40 s | no | ok | Image median 0.01347→0.00122 (flux scale broken); stars 529→3; unusable |
| Siril `rl` | M31 full 5967×3763 | `makepsf stars -sym` + `rl -iters=10 -mul` | 5.67 s | no | ok | RL step "Execution time: 4.93 s"; bgnoise R/G/B 1.663/1.302/1.214 → 3.200/2.790/2.757 |
| Siril `rl` | M31 full | `makepsf stars -sym` + `rl` (defaults) | 5.22 s | no | ok | RL step 4.61 s |
| GraXpert 3.0.2 | — | `-cmd` only accepts `{background-extraction,denoising}` | — | — | not available | Help confirms there is no deconvolution command in 3.0.2 (deconv-obj/deconv-stellar are in 3.1 RC only) |

## Denoise

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `denoise` (NL-Bayes) | M31 crop | `denoise` (cosmetic on, mod 1) | 0.42 s | no | ok | Box MAD G 1.679e-5→5.944e-6 (**−65 %**); bgnoise R/G/B 1.973/1.516/1.400 → 1.549/1.282/1.129; FWHM +0.0 %. Log prints `error: no suitable data in src fits` but the run continues and succeeds |
| Siril `denoise` | M31 crop | `-nocosmetic` | 0.45 s | no | ok | Same numbers as above (same error line) |
| Siril `denoise` | M31 crop | `-nocosmetic -mod=0.5` | 0.44 s | no | ok | Box MAD G 1.127e-5 (−33 %); bgnoise G 1.378 |
| Siril `denoise` | M31 crop | `-nocosmetic -da3d` | 12.77 s | no | ok | Box MAD G 3.76e-6 (**−78 %**); bgnoise G 1.241; FWHM +0.0 % |
| Siril `denoise` | M31 crop | `-nocosmetic -sos=3` | 1.17 s | no | ok | Box MAD G 5.232e-6 (−69 %); bgnoise G 1.259 |
| Siril `denoise` | M31 crop | `-nocosmetic -vst` | 0.41 s | no | ok | Box MAD G 5.598e-6 (−67 %); the help says VST is "usually not beneficial" for stacks |
| Siril `denoise` | M31 crop | `-nocosmetic -indep` | 0.70 s | no | ok | Box MAD G 4.893e-6 (−71 %); bgnoise G 1.190 |
| Siril `denoise` | M31 full | `denoise -nocosmetic` | 4.41 s | no | ok | "NL-Bayes execution time: 4.16 s"; bgnoise R/G/B 1.663/1.302/1.214 → 1.293/1.097/0.964 |
| GraXpert denoising | M31 crop | `-strength 0.5 -gpu true` (1st run) | 337.28 s | CoreML + CPU | ok | **296 s of this was a model download** ("AI version 3.0.2 not found locally, downloading..."), into `~/Library/Application Support/GraXpert/denoise-ai-models/3.0.2/model.onnx` |
| GraXpert denoising | M31 crop | `-strength 0.5 -gpu true` (model cached) | 48.70 s | CoreML + CPU | ok | `Used inference providers : ['CoreMLExecutionProvider', 'CPUExecutionProvider']`, but `number of nodes in the graph: 2527 number of nodes supported by CoreML: 78`. Box MAD G 1.679e-5→9.67e-6 (**−42 %**); bgnoise G 1.516→1.255; FWHM −0.0 % |
| GraXpert denoising | M31 crop | `-strength 0.5 -gpu false` | 63.29 s | no (CPUExecutionProvider) | ok | Output identical to GPU run in every measured number; GPU is 1.3× faster |
| GraXpert denoising | M31 crop | `-strength 1.0 -gpu true` | 44.54 s | CoreML + CPU | ok | Box MAD G 3.453e-6 (**−79 %**); bgnoise G 1.085; FWHM −0.7 % |
| GraXpert denoising | M31 full | `-strength 0.5 -gpu true` | **1172.62 s (19.5 min)** | CoreML + CPU | ok, just under the 20 min cap | user 4518 s; bgnoise R/G/B 1.663/1.302/1.214 → 1.387/1.125/1.019 (Siril NL-Bayes default: 1.293/1.097/0.964 in 4.4 s) |

## Plate solving

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `platesolve` | M31 crop | `platesolve -force`, user's default Siril config | 1.26 s | no | **solved** | 3.117″/px, focal 248.81 mm, pixel 3.76 µm, FOV 53′11.8″×39′53.9″, centre RA 00 42 48.775 Dec +41 16 17.165, "Up is +258.45 deg", 0.06′ from the header value. **The solve used the online NOMAD catalogue** ("Contacting server", "Fetched 1446 stars from NOMAD catalogue") because the user config's `core.catalogue_gaia_astro`/`_photo` still point to the deleted `…/stacking-astro/library/catalogues`. **Side effect:** "Saved focal length 248.81 and pixel size 3.76 as default values". This rewrote the user's Siril config (`focal_length` 248.949→248.814, `pixel_size` 3.76→3.7599999904632599) because `astrometry.update_default_scale = true`. Not reverted, see Findings |
| Siril `platesolve` | M31 crop / M31 full / IC 1848 | `-force -catalog=localgaia` with a scratch config (`-i`, catalogue paths → `~/Documents/astro/library/catalogues`) and `-o` offline | — | — | **not run** | Blocked in this session (permission refused) because it touches the Siril configuration. Scripts are ready: `work/ps_crop.ssf`, `ps_full.ssf`, `ps_ic.ssf` (IC 1848 needs `02:51:00,+60:25:00 -focal=248 -pixelsize=3.76` because its header has no metadata) |
| — | 20 mm Z6III wide field | — | — | — | known failure (not these data, not reproduced) | Stated in the brief. Siril's help says star detection is cropped to the centre for FOV > 5° unless `-nocrop` is passed. Related: the legacy run #78 (250 mm) itself recorded `"SPCC unavailable: solve error"` and fell back to PCC, yet the same image's crop solved here in 1.26 s |

## Photometric colour calibration (PCC / SPCC)

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `pcc` / `spcc` | M31 crop / full | `pcc -catalog=localgaia`; `spcc "-oscsensor=Sony IMX571" "-oscfilter=UV/IR Block" "-whiteref=Average Spiral Galaxy"` | — | — | **not run** | Needs a plate-solved image (see above). Scripts ready: `work/pcc_*.ssf`, `spcc_*.ssf` |
| Siril `spcc` (requirements) | — | `spcc_list …` | 0.32 s | no | listed | SPCC needs a sensor profile (`Sony IMX571` = ASI2600MC is in the OSC list), an OSC filter profile (36 listed, including `UV/IR Block`, `No filter`, `ZWO Duo-Band`, `Optolong L-Pro`, …), an optional OSC LPF, and a white reference (`Average Spiral Galaxy`, `Star, type G2(v)`, …). The help says "If one of the spectral data argument is omitted, the previously used value will be used", so an app must pass all of them explicitly. **The M31 capture's filter is not recorded** in `run.json` (only `"filter": "RGB"`, `filter_set: broadband`), so the PO has to supply it. The profiles are in `~/Library/Application Support/org.siril.Siril/siril-spcc-database`. The local Gaia xp_sampled catalogue is 48 `siril_cat1_healpix8_xpsamp_*.dat` files plus `siril_cat_healpix8_astro.dat` in `~/Documents/astro/library/catalogues` |
| Siril `pcc`/`spcc` | IC 1848 (dual-band) | — | — | — | not valid by construction | PCC/SPCC fit a white balance to broadband star photometry (Gaia BP/RP or spectra). Through a dual-band filter (Hα + [OIII] passbands) each channel sees only narrow lines, so star colours no longer follow the broadband catalogue, and the nebula is pure line emission with no "white". The legacy pipeline skipped them for this run ("palette hoo … SPCC + SCNR skipped"). Siril's `spcc -narrowband -rwl/-rbw…` mode exists, but it only rebalances to stated passbands; it is not a colour truth |

## Wavelets (à trous)

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `wavelet` + `wrecons` | M31 crop | `wavelet 6 2` (B-spline) + `wrecons 1 1 1 1 1 1` | 0.09 s | no | ok | 6 layers per channel. Identity reconstruction max \|Δ\| = 2.98e-8 (0.002 ADU16) → lossless |
| Siril `wavelet` + `wrecons` | M31 crop | `wavelet 4 1` (linear) + `wrecons 0 1 1 1` | 0.07 s | no | ok | 4 layers; dropping layer 1: box MAD G 1.679e-5→1.13e-5 |
| Siril `wavelet` + `wrecons` | M31 full | `wavelet 6 2` + `wrecons 1.5 1.2 1 1 1 1` | 0.98 s | no | ok | Layers are written to `$TMPDIR/{r,g,b}_rawdata.wave`, **538.9 MB per channel (1.6 GB) at full frame**. The fixed file names mean two concurrent Siril processes would overwrite each other's layers. The only output is the reconstructed image; individual layers are not exposed as FITS |

## Drizzle (applicability only — not run)

| Tool | Input | Flags | Wall time | GPU | Result | Notes |
|---|---|---|---|---|---|---|
| Siril `register`/`seqapplyreg -drizzle` | M31 / IC 1848 stacks | — | — | — | not applicable to finished stacks | Drizzle resamples **each registered sub-frame** onto a finer grid, so it needs the calibrated (debayered or CFA) light sequence plus a registration, and then a restack. It cannot run on `rgb_base.fits`. It would make sense here: M31 FWHM is 2.15–2.3 px at 3.12″/px, close to undersampled, and the memory notes say the captures have no dithering (0.5 px steps), which drizzle needs to work. That makes it a StackKit/E11 stacking option, not an E17 Studio process |

## Licences and integration

- **Siril:** GPLv3 (upstream). The app bundle has no LICENSE/COPYING file. `siril-cli -c` prints "Copyright ©
  2012-2026 team free-astro".
- **GraXpert:** GPLv3 (upstream). The app bundle has no top-level LICENSE file (only third-party
  `*.dist-info/LICENSE*`). The AI models are downloaded at first use to `~/Library/Application Support/GraXpert/`.
- Both are **invoked as host tools (separate processes), never bundled or linked**, consistent with the project rules
  (a missing tool greys the process with an install card).

## Findings

1. **Siril NL-Bayes denoise is the clear denoise winner.** Default settings cut the crop's star-free box MAD by 65 %
   in 0.42 s and the full frame took 4.4 s, with FWHM unchanged (+0.0 %). `-da3d` reaches −78 % in 12.8 s on the crop.
   `-mod=` gives a linear strength slider (0.5 → −33 %).
2. **GraXpert AI denoise works, but it is slow here.** It took 44–49 s on the crop and **1173 s (19.5 min) on the full
   frame**, just under the 20 min cap. At strength 0.5 it removes less noise than Siril's default (−42 % vs −65 % box
   MAD). At 1.0 it reaches −79 %. "GPU" means CoreML runs only **78 of 2527 graph nodes**, so it is only 1.3× faster
   than CPU and the output is identical. The first run also needs a ~300 s model download (network).
3. **Deconvolution does not pay off on these data.** Stars are already 2.15–2.3 px FWHM at 3.12″/px. Siril's default
   `rl` (gradient descent) is a measured no-op (FWHM ±0.5 %) with every PSF tried (stars, blind, Moffat). Every
   setting that shrinks FWHM by ≥ 9 % (`-mul` from 3 iterations, larger `-gdstep`, `sb`, `wiener`) produces dark rings
   50–7000σ deep around all 10 bright stars and raises background noise 1.4–6×. Wiener breaks the flux scale. No
   operating point removes ringing and narrows stars at the same time, and Siril has no deringing or star-mask option
   on `rl`.
4. **Plate solving works and is fast** (crop 1.26 s, 3.117″/px, centre 00 42 48.8 +41 16 17). Two traps for the app:
   (a) the user's Siril config still points the local Gaia catalogues at the deleted stacking-astro path, so Siril
   **silently fell back to the online NOMAD catalogue**; (b) `platesolve` **persists focal/pixel defaults into the
   user's Siril config** (`astrometry.update_default_scale=true`). The app should run Siril with its own config file
   (`-i`), set the catalogue paths there, and set `astrometry.update_default_scale=false`. IC 1848 has no
   FOCALLEN/XPIXSZ/RA/DEC in its header, so the app must supply them (focal 248 mm, pixel 3.76 µm, target
   coordinates). The local-Gaia offline solve, the full-frame solve and the IC 1848 solve were **not measured**
   (blocked).
5. **PCC/SPCC were not measured** (they depend on the blocked solves). The requirements are known: a plate-solved
   image, the sensor (`Sony IMX571` is present), the **filter, which the run metadata does not record**, a white
   reference, and the local Gaia xp_sampled catalogue (present). PCC/SPCC are invalid on dual-band captures such as
   IC 1848.
6. **Wavelets are instant and lossless** (0.09 s crop, 0.98 s full; identity reconstruction error 3e-8). Siril only
   returns the weighted recomposition, though: per-layer previews need the layers in-app, and the Metal port is
   trivial. The layers also go to fixed-name temp files (1.6 GB at full frame), which is unsafe with concurrent Siril
   processes.
7. **Drizzle** belongs to stacking (sequence + registration + restack), not to finishing, and is limited by the
   missing dithering in the captures.

**Recommended v1 subset**

- **Siril `denoise` (NL-Bayes, `-mod=` slider, optional `-da3d`)** — best noise reduction measured (−65 to −78 %),
  4 s at full frame, CPU, deterministic, no network.
- **Siril `platesolve` with an app-owned `-i` config pointing at the local Gaia catalogues** — the solve took 1.3 s and
  is needed for PCC/SPCC and annotation; the app must own the config because of the silent online fallback and the
  config side effect.
- **Siril `spcc`/`pcc` for broadband OSC only, with sensor, filter and white reference passed explicitly and greyed on
  dual-band** — the requirements are known, but the step is unmeasured here; finish the measurement before committing.
- **Wavelets in Metal (Siril `wavelet`/`wrecons` as the parity oracle)** — lossless, instant, and the real-time per-layer
  sliders the Studio wants are not available from Siril's CLI.
- **Defer: deconvolution** — measured no-op or ringing on 2.2 px stars, with no deringing in Siril and none in
  GraXpert 3.0.2.
- **Defer: GraXpert AI denoise** — 19.5 min at full frame with CoreML barely used, weaker than NL-Bayes at its default,
  and a first-run download; offer it later as optional.
- **Out of E17: drizzle** — a stacking option (StackKit/E11) needing dithered subs and a restack.
