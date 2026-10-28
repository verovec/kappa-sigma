Siril 1.4.4 colour-calibration transcripts, recorded on 2026-10-22 from run #78's 1024 × 768 crop
(`~/Documents/astro/fixtures/finish/crop/rgb_base.fits`, plate-solved first with card 0093's
script) with an app-owned `-i` config pointing at `~/Documents/astro/library/catalogues`:

- `m31-crop-spcc.log`: `spcc "-oscsensor=Sony IMX571" "-oscfilter=UV/IR Block" "-whiteref=Average Spiral Galaxy" -catalog=localgaia`
- `m31-crop-pcc.log`: `pcc -catalog=localgaia`
- `m31-crop-unsolved.log`: the same `spcc` on the crop with its WCS cards removed
- `m31-crop-lists.log`: `spcc_list oscsensor`, `oscfilter`, `whiteref`, `osclpf`
- `mono-lists.log` (2026-10-27, card 0140, no image loaded): `spcc_list monosensor`, `redfilter`,
  `greenfilter`, `bluefilter`

Progress-bar redraw lines and paths are stripped (`<WORK>`). Note: Siril 1.4.4 runs `spcc` with an
unknown sensor name (« Sony IMX999 ») as if it were the previous one — `ColourCalibrator` checks
every name against `spcc_list` first.
