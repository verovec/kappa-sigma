internal import Foundation
internal import ImageKit

/// StackKit's SwiftPM resource bundle (card 0129: the OpenNGC overlay), in the packaged app or in
/// tests (`KitBundle`: `Bundle.module` traps in the `.app`).
enum StackKitResources {
  /// The bundle holding `Catalogue/`.
  static let bundle = KitBundle.resolve(named: "AstroStack_StackKit.bundle") { Bundle.module }
}
