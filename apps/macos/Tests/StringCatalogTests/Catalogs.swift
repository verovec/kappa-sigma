import Foundation
import StringCatalog
import TestSupport
import Testing

/// The catalogs the app ships and the fixtures that prove the gate.
enum Catalogs {
  /// The targets that carry a `Localizable.xcstrings` (card 0073).
  static let targets = ["AstroStackApp", "RenderKit", "ProcessKit"]

  /// The source folder of `target`.
  static func folder(_ target: String) throws -> URL {
    let root = try ModuleBoundary.packageRoot(from: #filePath)
    return URL(fileURLWithPath: root).appendingPathComponent("Sources/\(target)")
  }

  /// The catalog `target` ships.
  static func shipped(_ target: String) throws -> StringCatalog {
    try StringCatalog(contentsOf: folder(target).appendingPathComponent("Localizable.xcstrings"))
  }

  /// Every Swift source of `target`.
  static func sources(_ target: String) throws -> [String] {
    let folder = try folder(target)
    let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil)
    return try (files?.allObjects as? [URL] ?? [])
      .filter { $0.pathExtension == "swift" }
      .map { try String(contentsOf: $0, encoding: .utf8) }
  }

  /// A fixture catalog of `Fixtures/`.
  static func fixture(_ name: String) throws -> StringCatalog {
    let url = try #require(
      Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: "xcstrings"))
    return try StringCatalog(contentsOf: url)
  }
}
