package import Foundation
internal import CryptoKit
internal import ImageIO
package import Testing
internal import UniformTypeIdentifiers

/// The finishing oracles (card 0067): the PO's validated v9 "HaPlus" chain recorded on run #78
/// and on a 1024×768 centre crop into `~/Documents/astro/fixtures/finish/` by
/// `scripts/record-finish-oracle.sh`. Only the manifest is committed (data rule R7); parity tests
/// (0050–0053, 0055, 0060) read the files through here and skip where the folder is absent.
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

  /// `<home>/Documents/astro/fixtures/finish` when it is a folder, `nil` otherwise.
  package static func root(home: URL) -> URL? {
    LiveFixtures.root(home: home).flatMap(finishFolder)
  }

  /// The folder for the current user, or `nil`.
  package static var root: URL? {
    LiveFixtures.root.flatMap(finishFolder)
  }

  private static func finishFolder(in fixtures: URL) -> URL? {
    let root = fixtures.appendingPathComponent("finish", isDirectory: true)
    let isFolder = (try? root.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory
    return isFolder == true ? root : nil
  }

  /// One sentence per file that is missing, changed, or not the recorded size.
  package static func verify(_ files: [FinishManifest.File], root: URL) throws -> [String] {
    try files.compactMap { file in
      let url = root.appendingPathComponent(file.path)
      guard FileManager.default.fileExists(atPath: url.path) else { return "\(file.path): missing" }
      guard try sha256(of: url) == file.sha256 else { return "\(file.path): sha256 differs" }
      let size = try dimensions(of: url)
      guard size == (file.width, file.height) else {
        return
          "\(file.path): \(size.width)×\(size.height), manifest says \(file.width)×\(file.height)"
      }
      return nil
    }
  }

  /// Hex SHA-256 of a file.
  package static func sha256(of url: URL) throws -> String {
    SHA256.hash(data: try Data(contentsOf: url, options: .mappedIfSafe))
      .map { String($0, radix: 16).leftPadded(to: 2) }.joined()
  }

  /// Width and height: NAXIS1/NAXIS2 of a FITS header, or the PNG's size.
  static func dimensions(of url: URL) throws -> (width: Int, height: Int) {
    if url.pathExtension == "fits" {
      let bytes = try FileHandle(forReadingFrom: url).read(upToCount: 2880) ?? Data()
      let header = String(bytes: bytes, encoding: .ascii) ?? ""
      func value(_ key: String) -> Int {
        let cards = stride(from: 0, to: header.count, by: 80).map {
          header.dropFirst($0).prefix(80)
        }
        let card = cards.first {
          $0.hasPrefix(key.padding(toLength: 8, withPad: " ", startingAt: 0))
        }
        return Int(
          card?.dropFirst(10).split(separator: "/").first?.trimmingCharacters(in: .whitespaces)
            ?? "") ?? 0
      }
      return (value("NAXIS1"), value("NAXIS2"))
    }
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
    else { throw FinishOracleError.unreadable(url.path) }
    return (
      properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
      properties[kCGImagePropertyPixelHeight] as? Int ?? 0
    )
  }

  /// Writes a grey 8-bit PNG (tests of `verify`).
  package static func writeTestPNG(width: Int, height: Int, to url: URL) throws {
    var pixels = [UInt8](repeating: 128, count: width * height)
    guard
      let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue),
      let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw FinishOracleError.unreadable(url.path) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw FinishOracleError.unreadable(url.path)
    }
  }
}

/// Why the oracle cannot be read.
package enum FinishOracleError: Error, Equatable {
  /// `Fixtures/finish/manifest.json` is not in TestSupport's resources.
  case manifestMissing
  /// A file that is not a readable image.
  case unreadable(String)
}

extension Trait where Self == ConditionTrait {
  /// Skips, with the reason, when `~/Documents/astro/fixtures/finish` is absent.
  package static var finishOracle: Self {
    .enabled(if: FinishOracle.root != nil, "~/Documents/astro/fixtures/finish absent")
  }
}

extension String {
  fileprivate func leftPadded(to length: Int) -> String {
    String(repeating: "0", count: max(0, length - count)) + self
  }
}
