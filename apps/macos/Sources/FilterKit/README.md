# FilterKit

The ONE filter list (CLAUDE.md): `Filter` (L R G B Ha OIII SII — cases, aliases, display order,
`rank`/`less`, colour aliases), its line physics (`Filter.Line`: wavelength, panel name, continuum
references) and the one-shot-colour clip filters (`FilterSet`: unknown, broadband, dual-band, with
the lines each plane carries). A leaf module with no dependency: StackKit (lanes, continuum fit,
bundle roles), ProcessKit (line processes) and the app (glossary words, pickers) all read it, so no
kit declares a second list.

## Adding a filter

1. A case on `Filter` with its wire token, its aliases in `aliases`, placed in display order.
2. Its physics in `Filter+Line.swift` when it is a line (wavelength, display name, continuum
   references) — `narrowband`/`broadband` follow.
3. `FilterKitTests.FilterTests` rows (list, aliases, rank, continuum).
4. Consumers: the app's glossary term `filter.<token>` fr/en (`GlossaryTests`), ProcessKit's
   `LinePanelDefaults` entry (its test fails otherwise) and the per-line help entries
   (`HelpCoverageTests+Params`).

Two StackKit helpers still spell tokens for their own reasons and are checked by their tests, not
derived: `CaptureManifest.knownFilters` (a glued-word splitter matched longest-first) and
`ChannelDetector.Options.order` (a default wheel order that stops at Hα). Revisit them with the
filter that needs them.

## Adding a clip filter

A case on `FilterSet` (its `rawValue` is on the wire: lane names, `lane_knobs`) with its `lines`;
the import picker, the lane split and the Stacking columns follow it (card 0134).
