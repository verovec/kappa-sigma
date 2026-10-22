internal import Foundation

/// What a history folder records besides its images (card 0087): the steps, the undone steps
/// and the snapshots, so a reopened project finds its history again. `<folder>.json` beside the
/// folder (the folder holds the images only), rewritten after every change.
struct HistoryManifest: Codable, Equatable {
  /// One step: its process, its values, its image and its layer outputs (role → file).
  struct Entry: Codable, Equatable {
    let processID: String
    let params: [ParamSet.Entry]
    let file: String
    let outputs: [String: String]
    /// The bundle layers a geometry step rewrote (id → file); absent before card 0090.
    var bundleLayers: [String: String]?
  }

  /// A named state.
  struct Snapshot: Codable, Equatable {
    let name: String
    let file: String?
  }

  /// The newest format this code reads and writes; 2: steps may carry `bundleLayers` (card
  /// 0090), which an older build would drop silently.
  static let version = 2
  /// The manifest of the history in `directory`: `<directory>.json`, beside it.
  static func url(of directory: URL) -> URL {
    directory.deletingLastPathComponent()
      .appendingPathComponent(directory.lastPathComponent + ".json")
  }

  let version: Int
  let nextNumber: Int
  let steps: [Entry]
  let undone: [Entry]
  let snapshots: [Snapshot]

  /// The manifest in `directory`, or nil when there is none (a fresh history).
  static func read(in directory: URL) throws -> Self? {
    let url = url(of: directory)
    guard FileManager.default.fileExists(atPath: url.path) else { return nil }
    let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
    guard manifest.version <= version else {
      throw HistoryError.unreadable("written by a newer format (\(manifest.version))")
    }
    return manifest
  }

  /// Writes the manifest into `directory`, atomically.
  func write(in directory: URL) throws {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    try encoder.encode(self).write(to: Self.url(of: directory), options: .atomic)
  }
}
