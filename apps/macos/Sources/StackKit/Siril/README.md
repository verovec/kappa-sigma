# StackKit/Siril — the Siril driver (card 0045)

Port of `../stacking-astro/internal/siril` (reference only). Siril does the pixel math; StackKit
writes its scripts and reads its output.

## Pieces

| Type | Role |
|---|---|
| `SirilCommand` | one typed case per verb; `line` renders it (no shell strings) |
| `SirilScript` | header `requires 1.2.0 / setext fits / set32bits` + one command per line, `\n`-terminated |
| `SirilScripts` | the legacy builders, one per recorded shape (masters, flats, calibrate/register, graded stack, parity probe, alignment, merge groups, mirror, neutralize, finish, combine, mono) |
| `StackClause`, `StackOptions` | the `stack` options in the legacy order; auto rejection: ≤ 7 frames percentile, ≥ 50 GESD, else winsorized |
| `CalibrationMasters` | `calibrate` arguments in the legacy order (`-dark -flat -bias -cc -opt -cfa -equalize_cfa -debayer`) |
| `GoFormat` | Go's `%g` (`strconv 'g' -1`) and `%.Nf`, for byte-identical numbers |
| `SirilLine`, `SirilOutput` | output lines (`log:` stripped, percent read the legacy way incl. `100.00%` → 0, `status:`), the one-line error hint |
| `SirilLimits`, `SirilVersion`, `SirilTool` | `setcpu`/`setmem` injection, the ≥ 1.4 version floor, `SIRIL_BIN` → app bundle |
| `SirilRunner` | script mode: `siril-cli -d dir -s dir/_astrostack.ssf` via swift-subprocess (struct of closures) |
| `SirilSession` | pipe mode: one `siril-cli -p -r in -w out` per session (actor), FIFOs opened read-write by us, restart on crash → `SirilError.restarted` |

**Mode:** `SirilMode.default` is `.script` (every oracle was recorded that way) until card 0048's
golden is byte-identical in `.pipe` too.

## Pipe protocol (Siril 1.4.4, checked)

`ready` once; per command `status: starting <verb>`, `log:` / `progress:` lines, then
`status: success|error <verb>`. An unknown verb answers a localized "Commande inconnue …" /
"Unknown command …" log line and `status: error`. Every verb the builders emit is accepted
(`LiveSirilTests`, with a negative control).

## Oracles

`SirilScriptTests` rebuilds all 60 scripts of the committed cases (golden single and two nights)
from their parameters and compares bytes. Rules no recording exercises (other rejections, fast
norm, rejection maps, feather, `-opt`, CFA without flat) are pinned by `StackClauseTests` with the
legacy unit tests' expectations. The real M31 cases' scripts (`~/Documents/astro/fixtures/oracle`)
are the next oracle, when 0048 drives a whole run.

## How to extend

- A new verb: add a `SirilCommand` case, its `line`, and a sample in `SirilCommand.samples`
  (`testSamplesCoverEveryVerb` fails otherwise; the live test then checks Siril accepts it).
- A new builder: port it from `scripts.go`, then pin it against a recorded script (or, without
  one, the legacy unit test's expected text).
- Never hand-format numbers: use `GoFormat` so a script stays byte-identical to the legacy one.
