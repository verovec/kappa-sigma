package import Foundation

/// HelpKit's SwiftPM resource bundle, for callers that resolve it themselves (`KitBundle` in the
/// packaged app, where `Bundle.module` traps); evaluate it only outside the `.app`.
package enum HelpKitResources {
  /// `Bundle.module` of HelpKit.
  package static var module: Bundle { .module }
}
