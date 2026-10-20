import Foundation

/// The committed Siril oracle of one legacy run's layers (`Fixtures/m31-run-layers.json`,
/// recorded by `scripts/record-fits-oracle.sh`) and where the files live on the PO's Mac.
enum M31RunLayers {
  struct Manifest: Decodable {
    struct Channel: Decodable {
      let mean: Double
      let min: Double
      let max: Double
    }

    struct File: Decodable {
      let name: String
      let sha256: String
      let width: Int
      let height: Int
      let channels: [Channel]
    }

    let run: String
    let siril: String
    let scale: Double
    let tolerance: Double
    let files: [File]
  }

  static let manifest: Manifest? = {
    guard
      let url = Bundle.module.url(forResource: "Fixtures/m31-run-layers", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(Manifest.self, from: data)
  }()

  /// `~/Documents/astro/runs/<run>`, when present.
  static var folder: URL? {
    guard let manifest else { return nil }
    let folder = URL(fileURLWithPath: NSHomeDirectory())
      .appendingPathComponent("Documents/astro/runs/\(manifest.run)")
    return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
  }

  /// The recorded layer names.
  static var names: [String] { manifest?.files.map(\.name) ?? [] }
}
