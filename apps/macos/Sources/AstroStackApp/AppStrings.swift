package import Foundation
internal import ImageKit

/// The app's string catalog, `Localizable.xcstrings`, compiled into `en.lproj`/`fr.lproj` of
/// the app's resource bundle by `CatalogPlugin`.
///
/// Every UI string is a `LocalizedStringResource` of this bundle: SwiftUI resolves it in the
/// view's `\.locale`, AppKit with `String(localized:)` in the user's languages
/// (`AppleLanguages`, which the language setting writes). `String(localized:bundle:)` is not
/// used: it follows the bundle's own preferred localizations, not the user's choice.
/// `#bundle` is not used either: `Bundle.module` traps in a packaged `.app` (`KitBundle`).
package nonisolated enum AppStrings {
  /// The app's resources: `Contents/Resources` in the `.app`, the build folder in tests.
  package static let bundle = KitBundle.resolve(named: "AstroStack_AstroStackApp.bundle") {
    .module
  }
}

extension LocalizedStringResource {
  /// `key` in the app's catalog; `locale` pins the language (tests), the user's otherwise.
  package nonisolated static func app(
    _ key: String.LocalizationValue, locale: Locale? = nil
  ) -> LocalizedStringResource {
    KitBundle.string(key, in: AppStrings.bundle, locale: locale)
  }
}
