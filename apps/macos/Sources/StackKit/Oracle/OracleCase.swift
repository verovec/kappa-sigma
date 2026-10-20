internal import CryptoKit
package import Foundation

/// A recorded run of the legacy engine, the oracle every StackKit port is pinned against.
///
/// The pixel-free files `../stacking-astro/cmd/oraclerec` writes per case (README.md here).
/// `load` checks each file the manifest lists against its sha256 before anything is decoded, so a
/// hand-edited or half-re-recorded case fails loudly instead of pinning the wrong behaviour.
package struct OracleCase: Sendable {
  /// The `record/` folder of the case.
  package let directory: URL
  /// How the case was recorded.
  package let manifest: OracleManifest

  /// Loads the case at `directory`, verifying every file hash of the manifest.
  package static func load(at directory: URL) throws -> Self {
    let manifestURL = directory.appendingPathComponent("manifest.json")
    guard FileManager.default.fileExists(atPath: manifestURL.path) else {
      throw OracleCaseError.missingManifest(path: directory.path)
    }
    let manifest = try decoder.decode(OracleManifest.self, from: Data(contentsOf: manifestURL))
    for (name, expected) in manifest.files.sorted(by: { $0.key < $1.key }) {
      let url = directory.appendingPathComponent(name)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw OracleCaseError.missingFile(name)
      }
      // Any other read failure (permissions, TCC on ~/Documents) surfaces as itself, with its path.
      let data = try Data(contentsOf: url)
      let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
      guard actual == expected.lowercased() else {
        throw OracleCaseError.hashMismatch(file: name)
      }
    }
    return Self(directory: directory, manifest: manifest)
  }

  // MARK: - Recorded files

  /// `run.json`.
  package func run() throws -> OracleRun { try decode("run.json") }
  /// `inventory.json`.
  package func inventory() throws -> OracleInventory { try decode("inventory.json") }
  /// `calibration.json`.
  package func calibration() throws -> OracleCalibration { try decode("calibration.json") }
  /// `grades.json`.
  package func grades() throws -> [OracleChannelGrades] { try decode("grades.json") }
  /// `selection.json`.
  package func selection() throws -> OracleSelection { try decode("selection.json") }
  /// `registration.json`.
  package func registration() throws -> OracleRegistration { try decode("registration.json") }

  /// `steps.txt`: each distinct progress step, first-seen order.
  package func steps() throws -> [String] {
    try text("steps.txt").split(separator: "\n").map(String.init)
  }

  /// `masters.sha256`: data-unit hashes of every master.
  package func masterHashes() throws -> [OracleHash] {
    try OracleHash.parse(text("masters.sha256"), file: "masters.sha256")
  }

  /// `bundle_layers.sha256`: data-unit hashes of the bundle layers (rgb_base, syn_*, aligned_*…).
  package func layerHashes() throws -> [OracleHash] {
    try OracleHash.parse(text("bundle_layers.sha256"), file: "bundle_layers.sha256")
  }

  /// `scripts/`: every Siril script, in emission order.
  package func scripts() throws -> [OracleScript] {
    let folder = directory.appendingPathComponent("scripts", isDirectory: true)
    return try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { $0.hasSuffix(".ssf") }
      .compactMap { name in
        OracleScript(
          name: name,
          text: try String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8))
      }
      .sorted { $0.number < $1.number }
  }

  // MARK: - Decoding

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.keyDecodingStrategy = .convertFromSnakeCase
    return decoder
  }()

  private func text(_ name: String) throws -> String {
    try String(contentsOf: directory.appendingPathComponent(name), encoding: .utf8)
  }

  private func decode<Value: Decodable>(_ name: String) throws -> Value {
    try Self.decoder.decode(
      Value.self, from: Data(contentsOf: directory.appendingPathComponent(name)))
  }
}
