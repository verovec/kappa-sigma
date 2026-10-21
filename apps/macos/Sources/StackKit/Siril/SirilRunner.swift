package import Foundation

/// Runs one script in its own `siril-cli` process (script mode).
///
/// `siril-cli -d <dir> -s <dir>/_astrostack.ssf`, as the legacy `Runner.Run`. A struct of
/// closures: tests substitute `run` with recorded behaviour.
package struct SirilRunner: Sendable {
  /// Runs `script` in `directory`, handing every output line to `onLine`; returns the raw log
  /// (stdout and stderr, one `\n` per line) or throws `SirilError.scriptFailed` with its cause.
  package var run:
    @Sendable (
      _ script: SirilScript, _ directory: URL, _ onLine: @escaping @Sendable (SirilLine) -> Void
    ) async throws -> String

  /// A runner from its closure (tests record scripts and play Siril's file side).
  package init(
    run:
      @escaping @Sendable (
        _ script: SirilScript, _ directory: URL, _ onLine: @escaping @Sendable (SirilLine) -> Void
      ) async throws -> String
  ) {
    self.run = run
  }

  /// A runner over the `siril-cli` at `binary`, with optional CPU/memory limits.
  package static func live(binary: String, limits: SirilLimits = SirilLimits()) -> Self {
    Self(run: { script, directory, onLine in
      try await runScript(script, in: directory, binary: binary, limits: limits, onLine: onLine)
    })
  }

  private static func runScript(
    _ script: SirilScript, in directory: URL, binary: String, limits: SirilLimits,
    onLine: @escaping @Sendable (SirilLine) -> Void
  ) async throws -> String {
    // Siril < 1.4 would silently ignore 1.4 syntax (`rgbcomp -lum=`): refuse it up front.
    _ = try await SirilTool.verify(binary)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let file = directory.appendingPathComponent("_astrostack.ssf")
    try Data(limits.apply(to: script.render()).utf8).write(to: file)
    let outcome = try await ToolProcess.runLines(
      binary, arguments: ["-d", directory.path, "-s", file.path]
    ) { line in onLine(SirilLine(parsing: line)) }
    guard outcome.exitCode == 0 else {
      throw SirilError.scriptFailed(
        exitCode: outcome.exitCode ?? -1, hint: SirilOutput.errorHint(log: outcome.log))
    }
    return outcome.log
  }
}
