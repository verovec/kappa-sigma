package import Foundation
internal import CryptoKit
package import Testing

/// The finishing oracles (card 0067).
///
/// The PO's validated v9 "HaPlus" chain is recorded on run #78 and on a 1024×768 centre crop into
/// `~/Documents/astro/fixtures/finish/` by `scripts/record-finish-oracle.sh`. Only the manifest is
/// committed (data rule R7). Parity tests (0050–0053, 0055, 0060) read the files through here and
/// skip where the folder is absent.
package enum FinishOracle {
  /// The stages the E12/E13 cards pin against.
  package static let requiredStages: Set<String> = [
    "screens_only", "hdr_only", "haplus_full", "stars_25", "stars_50", "stars_75", "starless",
  ]

  /// The committed manifest.
  package static func manifest() throws -> FinishManifest {
    guard
      let url = Bundle.module.url(forResource: "Fixtures/finish/manifest", withExtension: "json")
    else { throw FinishOracleError.manifestMissing }
    return try JSONDecoder().decode(FinishManifest.self, from: Data(contentsOf: url))
  }

  /// `<home>/Documents/astro/fixtures/finish` when it is a folder and live suites run
  /// (`ASTROSTACK_SKIP_LIVE` in `environment` not `1`), `nil` otherwise.
  package static func root(home: URL, environment: [String: String] = [:]) -> URL? {
    LiveFixtures.root(home: home, environment: environment).flatMap(finishFolder)
  }

  /// The folder for the current user and environment, or `nil`.
  package static var root: URL? {
    LiveFixtures.root.flatMap(finishFolder)
  }

  /// The legacy run folder the manifest names (`~/Documents/astro/runs/<run>`), if present.
  package static func runFolder(_ manifest: FinishManifest, home: URL) -> URL? {
    let folder = home.appendingPathComponent("Documents/astro/runs")
      .appendingPathComponent(manifest.provenance.run)
    return FileManager.default.fileExists(atPath: folder.path) ? folder : nil
  }

  private static func finishFolder(in fixtures: URL) -> URL? {
    let root = fixtures.appendingPathComponent("finish", isDirectory: true)
    let isFolder = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
    return isFolder == true ? root : nil
  }

  /// One sentence per file that is missing, changed, unreadable or not the recorded size; every
  /// file is checked. A file recorded with no size (a tool source) is checked by hash only.
  package static func verify(_ files: [FinishManifest.File], root: URL) -> [String] {
    files.compactMap { file in
      let url = root.appendingPathComponent(file.path)
      guard FileManager.default.fileExists(atPath: url.path) else { return "\(file.path): missing" }
      do {
        guard try sha256(of: url) == file.sha256 else { return "\(file.path): sha256 differs" }
        guard file.width > 0 || file.height > 0 else { return nil }
        let size = try FinishImages.dimensions(of: url)
        guard size == (file.width, file.height) else {
          return
            "\(file.path): \(size.width)×\(size.height), manifest says \(file.width)×\(file.height)"
        }
        return nil
      } catch {
        return "\(file.path): unreadable (\(error))"
      }
    }
  }

  /// Hex SHA-256 of a file.
  package static func sha256(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
      .map { String($0, radix: 16).leftPadded(to: 2) }.joined()
  }
}

extension Trait where Self == ConditionTrait {
  /// Skips, with the reason, when `~/Documents/astro/fixtures/finish` is absent (or live suites
  /// are off: `ASTROSTACK_SKIP_LIVE=1`).
  package static var finishOracle: Self {
    .enabled(if: FinishOracle.root != nil, "~/Documents/astro/fixtures/finish absent")
  }
}

extension String {
  fileprivate func leftPadded(to length: Int) -> String {
    String(repeating: "0", count: max(0, length - count)) + self
  }
}
