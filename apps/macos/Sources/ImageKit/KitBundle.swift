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
}
