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

**Mode:** `SirilMode.default` is `.pipe`: card 0048's golden single night is byte-identical in both
modes (`PreprocessLiveTests`, parameterised over the two). `SirilRunner.make(mode:binary:work:)`
builds either; `SirilRunner.pipe(_:)` replays each script as a `cd` to its folder plus its lines
in one session. The oracles were recorded in script mode, which stays one argument away.

**The pipe's command limit (card 0193).** Siril reads 512 bytes of its pipe at a time, newline
included (measured on 1.4.4): a command of 511 bytes is answered `status: error command too long or
malformed`, which names no verb, and a longer one is cut — its tail runs as a command of its own.
`SirilSession.maxCommandBytes` is 510. `SirilRunner.pipe(_:fallback:)` hands a script holding a
longer line (its `cd` counts) to the script-mode runner, whole: the same commands, read from a file.
`make(mode: .pipe…)` sets that fallback; the script still runs alone (`SirilSession.alone` holds the
queue) and a journal line says it left the pipe. Script mode was checked on the real Siril: a line
of 624 bytes is read whole. The session itself refuses a longer command, and a script holding one,
before sending anything (`SirilError.commandTooLong`); and an error status that arrives before the
command started fails that command even when it names no verb, instead of being waited out. What makes a command long is the scratch folder: under the default
`$TMPDIR` each master path is ~130 bytes, and a `calibrate` naming a bias, a dark, a flat and a
defect list passes the limit.

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
