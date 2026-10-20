import Foundation
import StackKit
import Synchronization

/// A `SirilRunner` that records every script and plays Siril's file side: the output a script
/// names (`stack … -out=X`, `save X`) appears as `X.fits`. `fail` decides, per script, to throw
/// after writing a partial output instead.
final class RecordingSiril: Sendable {
  struct Call: Sendable {
    var script: String
    var directory: URL
  }

  private let state = Mutex<[Call]>([])
  let fail: @Sendable (String) -> Bool
  let onRun: @Sendable (String) -> Void

  init(
    fail: @escaping @Sendable (String) -> Bool = { _ in false },
    onRun: @escaping @Sendable (String) -> Void = { _ in }
  ) {
    self.fail = fail
    self.onRun = onRun
  }

  var calls: [Call] { state.withLock { $0 } }

  var runner: SirilRunner {
    SirilRunner(run: { script, directory, _ in
      let text = script.render()
      self.state.withLock { $0.append(Call(script: text, directory: directory)) }
      self.onRun(text)
      guard let out = Self.output(of: text) else { return "" }
      try Data("partial".utf8).write(to: URL(fileURLWithPath: out + ".fits"))
      if self.fail(text) { throw SirilError.scriptFailed(exitCode: 1, hint: "fake failure") }
      return "log: done\n"
    })
  }

  /// The base path a script writes (`-out=` of its last stack, else its `save`).
  static func output(of script: String) -> String? {
    for line in script.split(separator: "\n").reversed() {
      if line.hasPrefix("stack "), let range = line.range(of: "-out=") {
        return String(line[range.upperBound...])
      }
      if line.hasPrefix("save ") { return String(line.dropFirst(5)) }
    }
    return nil
  }
}
