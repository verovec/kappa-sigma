package import Foundation
internal import ImageKit

/// RenderKit's resource bundle: the shader sources and the viewer's string catalog
/// (`Localizable.xcstrings`, compiled by `CatalogPlugin`).
package enum RenderKitResources {
  /// `Contents/Resources` in the packaged app, the build folder in tests (`KitBundle`).
  package static let bundle = KitBundle.resolve(named: "AstroStack_RenderKit.bundle") {
    .module
  }
}

extension LocalizedStringResource {
  /// `key` in RenderKit's catalog; `locale` pins the language (tests), the user's otherwise.
  package static func renderKit(
    _ key: String.LocalizationValue, locale: Locale? = nil
  ) -> LocalizedStringResource {
    KitBundle.string(key, in: RenderKitResources.bundle, locale: locale)
  }
}
