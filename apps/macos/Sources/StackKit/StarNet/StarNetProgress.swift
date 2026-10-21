package import Foundation
internal import Synchronization

/// The percentages StarNet prints as it works, from its output in arbitrary chunks.
///
/// StarNet2 writes `Working: 8.3%Working: 16.7%…` without line breaks, so every `N%` or `N.N%`
/// counts, not the first of a line (the legacy `(\d+)\s?%` read 8.3 % as 3 %). A percentage cut
/// between two chunks waits for the next one; values over 100 are ignored.
package final class StarNetProgress: Sendable {
  private let pending = Mutex("")

  /// An empty parser.
  package init() {}

  /// The percentages that `chunk` completes, in output order.
  package func append(_ chunk: Data) -> [Double] {
    let text = String(bytes: chunk, encoding: .utf8) ?? String(bytes: chunk, encoding: .isoLatin1)
    return pending.withLock { buffer in
      buffer += text ?? ""
      var percents: [Double] = []
      while let sign = buffer.firstIndex(of: "%") {
        let number = buffer[..<sign].reversed().drop { $0 == " " }
          .prefix { $0.isASCII && ($0.isNumber || $0 == ".") }
        if let value = Double(String(number.reversed())), value <= 100 { percents.append(value) }
        buffer.removeSubrange(...sign)
      }
      // Only a trailing number can still become a percentage.
      let tail = buffer.reversed().prefix { $0.isASCII && ($0.isNumber || $0 == "." || $0 == " ") }
      buffer = String(tail.reversed())
      return percents
    }
  }
}
