package import Foundation
internal import Synchronization

/// Cuts a byte stream arriving in arbitrary chunks into lines.
///
/// Lines end at `\n` (a trailing `\r` dropped); the unfinished tail waits for the next chunk.
/// Thread-safe: FileHandle calls its readability handler on its own queue.
package final class LineSplitter: Sendable {
  private let pending = Mutex(Data())

  /// An empty splitter.
  package init() {}

  /// The unfinished last line, at end of stream (empty when the stream ended on `\n`).
  package func flush() -> [String] {
    pending.withLock { buffer in
      defer { buffer.removeAll() }
      guard !buffer.isEmpty else { return [] }
      var line = buffer[...]
      if line.last == 0x0D { line = line.dropLast() }
      return [
        String(bytes: line, encoding: .utf8) ?? String(bytes: line, encoding: .isoLatin1) ?? ""
      ]
    }
  }

  /// The complete lines that `chunk` finishes.
  package func append(_ chunk: Data) -> [String] {
    pending.withLock { buffer in
      buffer.append(chunk)
      var lines: [String] = []
      while let newline = buffer.firstIndex(of: 0x0A) {
        var line = buffer[buffer.startIndex..<newline]
        if line.last == 0x0D { line = line.dropLast() }
        lines.append(
          String(bytes: line, encoding: .utf8) ?? String(bytes: line, encoding: .isoLatin1) ?? "")
        buffer.removeSubrange(buffer.startIndex...newline)
      }
      return lines
    }
  }
}
