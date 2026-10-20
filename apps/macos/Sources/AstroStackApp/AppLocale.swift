package import Foundation
internal import HelpKit

/// The locale the interface speaks: the language of its strings, the user's region for numbers.
///
/// `Locale.current` keeps the region's identifier (`en_FR`) when the user picks French for the
/// app, so a view handing it to a formatter would word French screens in English. Window roots
/// set `\.locale` to `interface` instead, and every formatter reads the view's `\.locale`.
package nonisolated enum AppLocale {
  /// The languages the catalogs and the glossary ship (HelpKit's list, pinned against the
  /// catalogs by `InfoPlistTests`).
  package static var languages: [String] { HelpIndex.locales }

  /// The interface language among `languages` for the user's preferences, with their region.
  package static func interface(
    preferences: [String] = Locale.preferredLanguages,
    region: Locale.Region? = Locale.current.region
  ) -> Locale {
    let language =
      Bundle.preferredLocalizations(from: languages, forPreferences: preferences).first ?? "en"
    // From the current locale, so the user's number, hour and calendar choices survive.
    var components = Locale.Components(locale: .current)
    components.languageComponents = Locale.Language.Components(languageCode: .init(language))
    components.region = region
    return Locale(components: components)
  }

  /// The language of `locale` if the app ships it, English otherwise.
  package static func language(of locale: Locale) -> String {
    let code = locale.language.languageCode?.identifier ?? "en"
    return languages.contains(code) ? code : "en"
  }
}
