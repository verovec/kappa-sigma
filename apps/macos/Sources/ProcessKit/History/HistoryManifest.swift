internal import Foundation

/// What a history folder records besides its images (card 0087): the steps, the undone steps
/// and the snapshots, so a reopened project finds its history again. `<folder>.json` beside the
/// folder (the folder holds the images only), rewritten after every change.
struct HistoryManifest: Codable, Equatable {
  /// One step: its process, its values, its image, its layer outputs (role → file) and the
  /// bundle layers it rewrote (id → file; absent from manifests written before card 0092), and
  /// whether it moved the pixels (absent = no: written only when true, card 0106), and the branch
  /// heads it read (absent = none, card 0118).
  struct Entry: Codable, Equatable {
    let processID: String
    let params: [ParamSet.Entry]
    let file: String
    let outputs: [String: String]
    let replaced: [String: String]?
    // Optional so a step that moves nothing writes no key: its manifest stays byte-identical.
    // swiftlint:disable:next discouraged_optional_boolean
    var movesPixels: Bool?
    // Absent when the step read no branch head (card 0118): older manifests stay byte-identical.
    var branchHeads: [String: String]?
  }

  /// A named state.
  struct Snapshot: Codable, Equatable {
    let name: String
    let file: String?
  }

  /// The format this code writes.
  static let version = 1
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
