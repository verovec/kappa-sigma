package import Foundation

/// Runs the user's GraXpert (`/Applications/GraXpert.app` or `GRAXPERT_APP`, never bundled) on one
/// FITS: `<input> -cli -cmd background-extraction -output <stem> -correction … -smoothing …`.
///
/// A struct of closures: tests substitute `run`. A missing app is `GraXpertError.missing`, never
/// a fallback (R2); a run past `timeout` is torn down (SIGTERM, then SIGKILL) and `timedOut`.
package struct GraXpertRunner: Sendable {
  /// What one extraction asks of GraXpert: its two CLI knobs, applied as given.
  package struct Options: Hashable, Sendable {
    /// `-smoothing`, 0…1.
    package var smoothing: Double
    /// `-correction`: Subtraction or Division.
    package var correction: BackgroundCorrection

    /// Options from their values.
    package init(smoothing: Double, correction: BackgroundCorrection) {
      self.smoothing = smoothing
      self.correction = correction
    }
  }

  /// Extracts the background of the FITS at `input` into `output`, handing every output line to
  /// `onProgress`; returns GraXpert's log.
  package var run:
    @Sendable (
      _ input: URL, _ output: URL, _ options: Options,
      _ onProgress: @escaping @Sendable (ToolProgress) -> Void
    ) async throws -> String

  /// A runner from its closure.
  package init(
    run:
      @escaping @Sendable (
        _ input: URL, _ output: URL, _ options: Options,
        _ onProgress: @escaping @Sendable (ToolProgress) -> Void
      ) async throws -> String
  ) {
    self.run = run
  }

  /// The runner over the GraXpert `tools` find, or `GraXpertError.missing` with the path looked at.
  package static func located(by tools: HostTools) async throws -> Self {
    let status = await tools.locate(.graxpert)
    guard status.isUsable else { throw GraXpertError.missing(path: status.path) }
    return live(app: status.path)
  }

  /// A runner over the `.app` at `app`, each run limited to `timeout`.
  package static func live(app: String, timeout: Duration = .seconds(30 * 60)) -> Self {
    Self(run: { input, output, options, onProgress in
      try await withThrowingTaskGroup(of: String.self) { group in
        group.addTask {
          try await execute(
            binary(inApp: app),
            arguments: arguments(input: input, output: output, options: options),
            output: output, onProgress: onProgress)
        }
        group.addTask {
          try await Task.sleep(for: timeout)
          throw GraXpertError.timedOut(after: timeout)
        }
        // Two tasks were just added: the first to finish decides, and cancelling the other tears
        // GraXpert down or ends the wait.
        guard let log = try await group.next() else { preconditionFailure("empty race") }
        group.cancelAll()
        return log
      }
    })
  }

  /// The command-line executable inside the app bundle.
  package static func binary(inApp app: String) -> String {
    app + "/Contents/MacOS/GraXpert"
  }

  /// The GraXpert 3 command line, the file first (positional, kept clear of the optional
  /// value of `-output`), then the operation and the two knobs; `-gpu` stays at the tool default.
  ///
  /// GraXpert 3.0 appends the input's extension to `-output` (`corrected.fits` would become
  /// `corrected.fits.fits`), so the stem of `output` is passed when their extensions agree.
  package static func arguments(input: URL, output: URL, options: Options) -> [String] {
    let sameExtension = output.pathExtension == input.pathExtension
    let named = sameExtension ? output.deletingPathExtension() : output
    return [
      input.path, "-cli", "-cmd", "background-extraction", "-output", named.path,
      "-correction", options.correction.graxpertArgument,
      "-smoothing", GoFormat.shortest(options.smoothing),
    ]
  }

  /// The legacy `firstErrorLine`: GraXpert logs a fatal AI/ONNX failure as `Critical error` and
  /// still exits 0, so a clean exit alone is not success.
  package static func criticalError(in log: String) -> String? {
    log.split(separator: "\n").first { $0.contains("Critical error") }
      .map { $0.trimmingCharacters(in: .whitespaces) }
  }

  private static func execute(
    _ binary: String, arguments: [String], output: URL,
    onProgress: @escaping @Sendable (ToolProgress) -> Void
  ) async throws -> String {
    let outcome = try await ToolProcess.runLines(binary, arguments: arguments) { line in
      onProgress(ToolProgress(parsing: line))
    }
    guard outcome.exitCode == 0 else {
      throw GraXpertError.failed(exitCode: outcome.exitCode, log: outcome.log)
    }
    if let line = criticalError(in: outcome.log) { throw GraXpertError.reportedError(line: line) }
    guard FileManager.default.fileExists(atPath: output.path) else {
      throw GraXpertError.noOutput(path: output.path)
    }
    return outcome.log
  }
}
