Siril 1.4.4 `platesolve` transcripts, recorded on 2026-10-22 from run #78's 1024 × 768 crop
(`~/Documents/astro/fixtures/finish/crop/rgb_base.fits`) with an app-owned `-i` config pointing at
the local Gaia catalogues (`~/Documents/astro/library/catalogues`):

- `m31-crop-solved.log`: `platesolve 10.68333,41.26917 -force -focal=250 -pixelsize=3.76 -catalog=localgaia`
- `m31-crop-failed.log`: the same image told it is at 83.75000,-5.38333 (M42), `-radius=0`
- `ic1848-fr.log`: the PO's IC 1848 stack solved on 2026-10-24 by a Siril speaking French
  (`LANG=fr_FR.UTF-8`, before card 0124): `platesolve 42.75,60.41667 -focal=248 -pixelsize=3.76`

Paths are replaced by `<WORK>` (and Siril's Python venv by `<VENV>`). `PlateSolverTests` replays them through a fake `SirilRunner`.
