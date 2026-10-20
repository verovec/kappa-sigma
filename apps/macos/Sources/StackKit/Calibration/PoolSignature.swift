internal import CryptoKit
internal import Foundation

/// The content signature of the raw frames a master was stacked from, kept in its `.sig`
/// sidecar (`poolSignature`, `formatPoolSig`): unchanged frames, identical master, reuse it.
package enum PoolSignature {
  /// sha256 (hex) of each frame's `path|size|mtime ns`, sorted, so the order does not matter.
  /// A frame that cannot be read signs as `path|?`. The legacy engine's signatures cannot match
  /// anyway: the frames they signed moved out of the repo (R7), so each master rebuilds once.
  package static func of(_ paths: [String]) -> String {
    let parts = paths.map { path -> String in
      guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
        let size = attributes[.size] as? Int, let modified = attributes[.modificationDate] as? Date
      else { return "\(path)|?" }
      let nanoseconds = Int64((modified.timeIntervalSince1970 * 1e9).rounded())
      return "\(path)|\(size)|\(nanoseconds)"
    }
    let digest = SHA256.hash(data: Data(parts.sorted().joined(separator: "\n").utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  /// The sidecar text (v2): the pool hash, then its depth.
  package static func format(hash: String, frameCount: Int) -> String {
    "\(hash)\n\(frameCount)"
  }

  /// A sidecar's hash and depth (v1 carries the hash alone: depth 0); `nil` when absent.
  package static func read(at path: String) -> (hash: String, frameCount: Int)? {
    guard let data = FileManager.default.contents(atPath: path),
      let text = String(bytes: data, encoding: .utf8)
    else { return nil }
    let lines = text.trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n", maxSplits: 2, omittingEmptySubsequences: false)
    let hash = lines.first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
    let count = lines.count > 1 ? Int(lines[1].trimmingCharacters(in: .whitespaces)) ?? 0 : 0
    return (hash, count)
  }

  /// The `.sig` beside a master `.fits`.
  package static func sidecar(of masterPath: String) -> String {
    (masterPath.hasSuffix(".fits") ? String(masterPath.dropLast(5)) : masterPath) + ".sig"
  }

  /// Whether the master at `master` was stacked from exactly `frames` (`builtFromSet`); a master
  /// without a sidecar proves nothing and is rebuilt once.
  package static func proves(master: String, builtFrom frames: [String]) -> Bool {
    guard let recorded = read(at: sidecar(of: master)), !recorded.hash.isEmpty else { return false }
    return recorded.hash == of(frames)
  }
}
