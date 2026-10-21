package import Foundation
package import HelpKit
internal import ImageKit
internal import OSLog

/// The glossary as the app shows it: a term's label and definition in a view's locale.
package nonisolated enum AppGlossary {
  /// HelpKit's glossary: `Contents/Resources` in the `.app`, the build folder in tests.
  package static let glossary = Glossary(bundle: helpBundle)
  /// The preprocessing knobs' words (`knobs.json`, card 0070): `knob.<id>` and its choices.
  package static let knobs = Glossary(bundle: helpBundle, file: "knobs.json")

  private static let helpBundle = KitBundle.resolve(named: "AstroStack_HelpKit.bundle") {
    HelpKitResources.module
  }

  /// The term `id` of `glossary` in the language of `locale`: French or English, English
  /// otherwise.
  package static func term(
    _ id: String, locale: Locale, in glossary: Glossary = glossary
  ) -> Glossary.Term {
    let language = AppLocale.language(of: locale)
    if let term = glossary.term(id, locale: language) { return term }
    // GlossaryTests gates the SwiftPM build; this catches a packaging break (bundle not copied).
    logger.fault("glossary term \(id, privacy: .public) missing in \(language, privacy: .public)")
    return Glossary.Term(label: id, definition: "")
  }

  private static let logger = Logger(subsystem: "fr.astrostack", category: "App/glossary")

  /// The label of `id` of `glossary` in `locale`.
  package static func label(_ id: String, locale: Locale, in glossary: Glossary = glossary)
    -> String
  {
    term(id, locale: locale, in: glossary).label
  }
}
