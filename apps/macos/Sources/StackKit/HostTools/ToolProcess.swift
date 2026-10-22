internal import Foundation
internal import Subprocess
internal import System

/// One run of a host tool whose output is read line by line (Siril's script mode, GraXpert):
/// the swift-subprocess call, the teardown on cancellation and the line splitting, once.
package enum ToolProcess {
  /// How the tool ended and everything it printed.
  package struct Outcome: Sendable {
    /// The exit code, or nil when a signal ended the tool.
    package let exitCode: Int32?
    /// stdout and stderr, one `\n` per line.
    package let log: String

    /// An outcome from its parts.
    package init(exitCode: Int32?, log: String) {
      self.exitCode = exitCode
      self.log = log
    }
  }

  /// Runs `binary` with `arguments`, handing every line to `onLine` as it arrives.
  ///
  /// Lines end at `\n` only, with no length cap (the legacy bufio.Scanner's rule). Cancelling the
  /// task stops the tool: SIGTERM, then SIGKILL two seconds later.
  package static func runLines(
    _ binary: String, arguments: [String], onLine: @escaping @Sendable (String) -> Void
  ) async throws -> Outcome {
    var options = PlatformOptions()
    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
    let result = try await Subprocess.run(
      .path(FilePath(binary)), arguments: Arguments(arguments), platformOptions: options,
      input: .none, output: .sequence, error: .combinedWithOutput
    ) { execution in
      let splitter = LineSplitter()
      var log = ""
      func take(_ lines: [String]) {
        for line in lines {
          log += line + "\n"
          onLine(line)
        }
      }
      for try await buffer in execution.standardOutput {
        take(splitter.append(Data(buffer: buffer)))
      }
      take(splitter.flush())
      return log
    }
    let code: Int32? = if case .exited(let value) = result.terminationStatus { value } else { nil }
    return Outcome(exitCode: code, log: result.closureResult)
  }
}
