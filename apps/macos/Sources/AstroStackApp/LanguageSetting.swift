package import Foundation

/// The interface language the user chose in Settings: the system's, French or English.
///
/// Written as `AppleLanguages` in the app's own defaults domain, which Foundation and AppKit
/// read at launch: the choice takes effect on relaunch (menus and document titles do not follow
/// a live switch).
package struct LanguageSetting {
  /// A choice of the Language picker.
  package enum Choice: String, CaseIterable, Sendable {
    case system
    case french = "fr"
    case english = "en"
  }

  private static let key = "AppleLanguages"
  private let defaults: UserDefaults
  private let domain: String

  /// The setting stored in `defaults`, whose own persistent domain is `domain` (the bundle
  /// identifier for the app, the suite name for a scratch suite).
  package init(
    defaults: UserDefaults = .standard,
    domain: String = Bundle.main.bundleIdentifier ?? "fr.astrostack.AstroStack"
  ) {
    self.defaults = defaults
    self.domain = domain
  }

  /// The current choice, read and written in the app's own domain only.
  ///
  /// Read anywhere else, `AppleLanguages` falls through to the system's global list. A per-app
  /// language set in System Settings (`fr-FR`) reads as its language.
  package var choice: Choice {
    get {
      let languages = defaults.persistentDomain(forName: domain)?[Self.key] as? [String]
      let code = languages?.first.flatMap { Locale.Language(identifier: $0).languageCode }
      return code.flatMap { Choice(rawValue: $0.identifier) } ?? .system
    }
    nonmutating set {
      var values = defaults.persistentDomain(forName: domain) ?? [:]
      values[Self.key] = newValue == .system ? nil : [newValue.rawValue]
      defaults.setPersistentDomain(values, forName: domain)
    }
  }
}
