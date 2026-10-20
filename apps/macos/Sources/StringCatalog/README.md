# StringCatalog

The localisation seam (card 0073): reads `Localizable.xcstrings`, gates it, and compiles it into
the `en.lproj` / `fr.lproj` tables Foundation resolves. Foundation only, no UI. Used at build time
by `CatalogTool` (through the `CatalogPlugin` build-tool plugin) and at test time by the coverage
gate; the app never links it.

## Why a plugin compiles the catalogs

SwiftPM on a Command Line Tools host has no `xcstringstool`: an `.xcstrings` resource is copied as
is and the app shows its keys in every language. So each target **excludes** its catalog from its
resources and lists `plugins: ["CatalogPlugin"]`; the plugin runs `CatalogTool <catalog> <folder>`
and the generated `<language>.lproj/Localizable.{strings,stringsdict}` become the target's localized
resources, identically under CLT and Xcode. A catalog that fails the gate **fails the build**.

## What exists

- `StringCatalog`: the house subset of the format — one `stringUnit` per language, or `plural`
  variations of one number. `StringCatalog.languages` = `en`, `fr` (E20: English source, French
  complete).
- `CatalogAudit.violations(of:used:)`: missing or untranslated value, format specifiers that differ
  from the key's (`FormatSpecifiers`, positional indexes dropped), unsupported variations, and — with
  `used` — stale keys. `CatalogAudit.uncatalogued(in:file:catalog:)`: a source literal a user reads
  that is not a key (literals without a letter and literals passed to `systemImage:`, `verbatim:`…
  are code, not text).
- `LiteralShape`: matches a key (`Night of %@`) to the literal producing it
  (`"Night of \(session)"`) without knowing the interpolated types.
- `CatalogCompiler`: sorted, escaped `.strings`; plurals as a `.stringsdict` rule.

## Rules for a UI string

- Write it in English in the code, as a resource of the target's catalog: `.app("…")` in the app,
  `.renderKit("…")` in RenderKit, `ProcessKitResources.title(_:)` for registry titles. SwiftUI shows
  a `LocalizedStringResource` in the view's `\.locale`; AppKit and models resolve it with
  `String(localized:)` in the user's languages. Never `String(localized:bundle:)` (it follows the
  bundle's preferred localizations, not `AppleLanguages`), never `#bundle`/`Bundle.module` (traps in
  the packaged `.app`; kits resolve their bundle with `KitBundle`).
- Add the key with `en` and `fr` values, state `translated`, to the target's `Localizable.xcstrings`.
  The key is the literal with `%@` for a string, `%lld` for an integer, `%lf` for a double.
- A count that changes the words is a `plural` variation of a key with exactly one number
  (`"%lld frames"`); compose longer sentences by interpolating that resource (nested resources
  resolve in the outer one's language).
- A literal `%` only in a key that has an argument (`%%` there); Foundation keeps a bare `%` in a key
  without arguments, which the gate cannot tell from a specifier.
- Tests resolve with an explicit locale (`resource.locale = Locale(identifier: "fr")`), never the
  host's languages.
- Where the gates run: `StringCatalogTests` (languages, specifiers, stale keys of the app and
  RenderKit), `ProcessKitTests/ProcessTitleCatalogTests` (catalog == registry titles),
  `AstroStackAppTests/ImportSheetTests` (no English literal in the migrated screens — add a screen
  to `migrated` when it is migrated).
