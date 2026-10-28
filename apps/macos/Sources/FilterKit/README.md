# FilterKit

The ONE filter list (CLAUDE.md): `Filter` (L R G B Ha OIII SII Hb NII — cases, aliases, display order,
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

One StackKit helper still spells tokens: `CaptureManifest.knownFilters`, the glued-word splitter
(`LLLRGBHaHa`), lists the short tokens it may split on, longest first within a collision group —
deriving it from every alias would change what a folder name parses as. Revisit it, with its own
tests, with the filter that needs it.

## Adding a clip filter

A case on `FilterSet` (its `rawValue` is on the wire: lane names `<filter>-<rawValue>`,
`lane_knobs` keys, import overrides) with its `lines` and `mixesLines`; the import picker
(`FilterSet.allCases`), the lane suffix, the split (`syn_<line>`), the Stacking columns and the
profile match follow it. Add the glossary term `filterSet.<rawValue>` fr/en (`GlossaryTests`).
The pixel classifier only ever measures broadband or dual-band: another clip is asserted by the
user at import.
