import Foundation
import StackKit
import TestSupport

/// The recorded cases that live outside the repo: `<fixtures>/oracle/<case>/record`.
enum OracleLiveCases {
  /// The live case `name` under `home`, or `nil` when the fixture root or the case is absent.
  static func find(_ name: String, home: URL) throws -> OracleCase? {
    guard let root = LiveFixtures.root(home: home) else { return nil }
    let record = root.appendingPathComponent("oracle/\(name)/record", isDirectory: true)
    guard
      FileManager.default.fileExists(atPath: record.appendingPathComponent("manifest.json").path)
    else { return nil }
    return try OracleCase.load(at: record)
  }
}
