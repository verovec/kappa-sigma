internal import CryptoKit
package import Foundation

/// One stacked lane's checkpoint (card 0097), `lanes/<lane>.json` in the run's output folder:
/// the lane's outcome as the run returned it and what it was stacked from, so a resume reuses it
/// only for the same frames and the same settings.
package struct LaneRecord: Codable, Equatable, Sendable {
  /// The folder the records live in, inside the output folder.
  package static let folderName = "lanes"

  /// The format version.
  package var version = 1
  /// Digest of the lane's light frames, every calibration frame and the library masters.
  package var frames: String
  /// Digest of the settings applied.
  package var settings: String
  package var outcome: ChannelOutcome

  /// The record of `outcome`, stacked from `lane` of `plan` under `request`.
  package init(_ outcome: ChannelOutcome, lane: String, plan: NightPlan, request: PreprocessRequest)
  {
    frames = Self.framesDigest(lane, plan: plan, request: request)
    settings = Self.settingsDigest(request)
    self.outcome = outcome
  }

  /// Why this record cannot stand for `lane` of `request`; nil when it can (its master, when it
  /// has one, still in the output folder).
  package func staleReason(lane: String, plan: NightPlan, request: PreprocessRequest) -> String? {
    if outcome.error != nil { return "it failed" }
    if frames != Self.framesDigest(lane, plan: plan, request: request) {
      return "the frames changed"
    }
    if settings != Self.settingsDigest(request) { return "the settings changed" }
    if let master = master(in: request.output),
      !FileManager.default.fileExists(atPath: master.path)
    {
      return "its master is gone"
    }
    return nil
  }

  /// The outcome as it stands in `output`: its master found by name there, wherever the folder
  /// was when the lane ran (a project moved or renamed in the Finder keeps its lanes).
  package func outcome(in output: URL) -> ChannelOutcome {
    var outcome = outcome
    outcome.masterPath = master(in: output)?.path
    return outcome
  }

  private func master(in output: URL) -> URL? {
    outcome.masterPath.map {
      output.appendingPathComponent(URL(fileURLWithPath: $0).lastPathComponent)
    }
  }

  /// Writes `output/lanes/<lane>.json`, replaced atomically.
  package func write(to output: URL) throws {
    let folder = output.appendingPathComponent(Self.folderName, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.nonConformingFloatEncodingStrategy = Self.nonFinite
    try encoder.encode(self).write(to: Self.url(outcome.filter, in: output), options: .atomic)
  }

  /// The record of `lane` in `output`.
  package static func read(lane: String, from output: URL) throws -> Self {
    let decoder = JSONDecoder()
    decoder.nonConformingFloatDecodingStrategy = .convertFromString(
      positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")
    return try decoder.decode(Self.self, from: Data(contentsOf: url(lane, in: output)))
  }

  /// A record of `lane` is in `output`, readable or not.
  package static func exists(lane: String, in output: URL) -> Bool {
    FileManager.default.fileExists(atPath: url(lane, in: output).path)
  }

  /// Real measurements hold NaN and ±∞ (a frame Siril could not measure): JSON has no number for
  /// them, so they are written as strings — a record must never fail on the data it keeps.
  private static let nonFinite = JSONEncoder.NonConformingFloatEncodingStrategy.convertToString(
    positiveInfinity: "+inf", negativeInfinity: "-inf", nan: "nan")

  private static func url(_ lane: String, in output: URL) -> URL {
    output.appendingPathComponent(folderName, isDirectory: true).appendingPathComponent(
      lane + ".json")
  }

  /// The lane's light sets (key and frames), the calibration frames and the library: what the
  /// lane's master is made of.
  ///
  /// Each file counts by path, size and modification time: a master rebuilt or a frame replaced
  /// in place changes it.
  static func framesDigest(_ lane: String, plan: NightPlan, request: PreprocessRequest) -> String {
    var text = ""
    for group in plan.channels[lane] ?? [] {
      text += String(reflecting: group.key) + "\n" + files(group.frames.map(\.path))
    }
    for set in request.inventory.sets where set.key.type != .light {
      text += "\n" + String(reflecting: set.key) + "\n" + files(set.frames.map(\.path))
    }
    text += "\n" + files(request.library.map(\.path))
    return digest(text)
  }

  /// One line per path: the path, its size and its modification time (0 for a missing file).
  private static func files(_ paths: [String]) -> String {
    paths.map { path in
      let attributes = try? FileManager.default.attributesOfItem(atPath: path)
      let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
      let modified = (attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
      return "\(path) \(size) \(modified)"
    }.joined(separator: "\n")
  }

  /// Every knob, as applied: a knob added by a later build changes it (the lane re-runs).
  static func settingsDigest(_ request: PreprocessRequest) -> String {
    digest(String(reflecting: request.settings))
  }

  private static func digest(_ text: String) -> String {
    SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
