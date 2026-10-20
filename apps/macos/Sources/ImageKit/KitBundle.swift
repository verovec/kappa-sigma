package import Foundation

/// Finds a kit's SwiftPM resource bundle in the packaged app as well as in tests.
///
/// `scripts/app-bundle.sh` copies resource bundles into `Contents/Resources`, where SwiftPM's
/// generated `Bundle.module` does not look (it checks the `.app` root, then the absolute build
/// folder, and traps when neither exists). Every kit with resources resolves its bundle here.
package enum KitBundle {
  /// The bundle `named` (`AstroStack_<Kit>.bundle`) in `resources` when it is there, otherwise
  /// `fallback()` — the kit's `Bundle.module`, evaluated only when needed.
  package static func resolve(
    named name: String, resources: URL? = Bundle.main.resourceURL,
    fallback: () -> Bundle
  ) -> Bundle {
    if let resources, let packaged = Bundle(url: resources.appendingPathComponent(name)) {
      return packaged
    }
    return fallback()
  }

  /// `key` in the string catalog compiled into `bundle` (card 0073); `locale` pins the language
  /// (tests), the user's languages (`AppleLanguages`) otherwise.
  package static func string(
    _ key: String.LocalizationValue, in bundle: Bundle, locale: Locale? = nil
  ) -> LocalizedStringResource {
    var resource = LocalizedStringResource(key, bundle: .atURL(bundle.bundleURL))
    if let locale { resource.locale = locale }
    return resource
  }
}
