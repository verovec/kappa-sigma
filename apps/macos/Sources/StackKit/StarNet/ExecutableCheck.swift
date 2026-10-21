package import Foundation

/// Whether this Mac can launch a tool binary: an executable bit is not enough, an Intel-only
/// program needs Rosetta on Apple silicon (the user's StarNet2 is x86_64).
package enum ExecutableCheck {
  /// Where Rosetta 2 lives once installed.
  package static let rosetta = "/Library/Apple/usr/share/rosetta/rosetta"

  /// The CPU types of the Mach-O at `url` (both slices of a universal binary); empty for a script
  /// or anything that is not Mach-O.
  package static func architectures(of url: URL) -> [String] {
    guard let handle = try? FileHandle(forReadingFrom: url),
      let bytes = try? handle.read(upToCount: 4096).map(Array.init), bytes.count >= 8
    else { return [] }
    let little = { (offset: Int) in
      (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * $1) }
    }
    let big = { (offset: Int) in (0..<4).reduce(UInt32(0)) { $0 << 8 | UInt32(bytes[offset + $1]) }
    }
    switch big(0) {
    case 0xCFFA_EDFE, 0xCEFA_EDFE:  // MH_MAGIC_64 / MH_MAGIC, little-endian on disk
      return [name(of: little(4))]
    case 0xCAFE_BABE, 0xCAFE_BABF:  // FAT_MAGIC / FAT_MAGIC_64, big-endian
      let entry = big(0) == 0xCAFE_BABE ? 20 : 32
      return (0..<Int(big(4))).compactMap { slice in
        let offset = 8 + slice * entry
        return offset + 4 <= bytes.count ? name(of: big(offset)) : nil
      }
    default:
      return []
    }
  }

  /// Why the binary at `path` cannot be launched here, or `nil`.
  package static func refusal(
    path: String, rosettaInstalled: Bool = FileManager.default.fileExists(atPath: rosetta)
  ) -> String? {
    let found = architectures(of: URL(fileURLWithPath: path))
    guard !found.isEmpty, !found.contains("arm64") else { return nil }
    guard found.contains("x86_64"), !rosettaInstalled else { return nil }
    return "\(path) is an Intel (x86_64) program and Rosetta is not installed: "
      + "install Rosetta (softwareupdate --install-rosetta) or an Apple-silicon build"
  }

  private static func name(of cpuType: UInt32) -> String {
    switch cpuType {
    case 0x0100_000C: "arm64"
    case 0x0100_0007: "x86_64"
    default: String(cpuType, radix: 16)
    }
  }
}
