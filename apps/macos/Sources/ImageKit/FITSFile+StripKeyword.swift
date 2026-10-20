package import Foundation

extension FITSFile {
  /// Blanks, in place, every primary-header card whose keyword is `keyword` (`fits.StripKeyword`).
  ///
  /// The card becomes 80 spaces, so the header keeps its size and the data unit does not move.
  /// The comparison ignores case, as the legacy one did. A file without the card is not written.
  package static func stripKeyword(_ keyword: String, at url: URL) throws {
    let key = Array(keyword.uppercased().utf8)
    let handle = try FileHandle(forUpdating: url)
    defer { try? handle.close() }
    var offset: UInt64 = 0
    while true {
      try handle.seek(toOffset: offset)
      guard let data = try handle.read(upToCount: block), data.count == block else {
        throw FITSFileError(path: url.path, reason: .noHeaderEnd)
      }
      var bytes = [UInt8](data)
      let (changed, ended) = blank(key, in: &bytes)
      if changed {
        try handle.seek(toOffset: offset)
        try handle.write(contentsOf: bytes)
      }
      if ended { return }
      offset += UInt64(block)
    }
  }

  /// Blanks the cards of one header block named `key`; reports whether any changed and whether
  /// the block holds END.
  private static func blank(_ key: [UInt8], in bytes: inout [UInt8]) -> (changed: Bool, ended: Bool)
  {
    var changed = false
    for start in stride(from: 0, to: block, by: cardLength) {
      let name = bytes[start..<start + 8].reversed().drop { $0 == 0x20 }.reversed()
        .drop { $0 == 0x20 }.map { $0 >= 0x61 && $0 <= 0x7A ? $0 - 0x20 : $0 }
      if name == Array("END".utf8) { return (changed, true) }
      if name == key {
        bytes.replaceSubrange(
          start..<start + cardLength, with: repeatElement(0x20, count: cardLength))
        changed = true
      }
    }
    return (changed, false)
  }
}
