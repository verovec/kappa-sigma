package import Foundation
internal import ImageKit

/// ProcessKit's resource bundle: the process shaders and the string catalog of process,
/// parameter and palette titles (`Localizable.xcstrings`, compiled by `CatalogPlugin`).
package enum ProcessKitResources {
  /// `Contents/Resources` in the packaged app, the build folder in tests (`KitBundle`).
  package static let bundle = KitBundle.resolve(named: "AstroStack_ProcessKit.bundle") {
    .module
  }

  /// A title of the registry (`ImageProcess.title`, `ParamSpec.title`, `Palette.title`) as the
  /// panel shows it: the English title is the catalog key.
  package static func title(_ title: String, locale: Locale? = nil) -> LocalizedStringResource {
    KitBundle.string(String.LocalizationValue(title), in: bundle, locale: locale)
  }
}
