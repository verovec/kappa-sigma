package import Foundation
package import ImageKit
internal import Subprocess
internal import System

/// Runs StarNet (user install, never bundled: no public licence) on one 16-bit TIFF.
///
/// A struct of closures: tests substitute `run`. The binary comes from `HostTools` (`STARNET_BIN`,
/// else `/usr/local/bin/starnet2`); a missing one is `StarNetError.missing`, never a fallback.
package struct StarNetRunner: Sendable {
  /// Turns the TIFF at `input` into its starless at `output`, handing every progress percentage
  /// to `onProgress`; returns StarNet's log.
  package var run:
    @Sendable (_ input: URL, _ output: URL, _ onProgress: @escaping @Sendable (Double) -> Void)
      async throws -> String

  /// A runner from its closure.
  package init(
    run:
      @escaping @Sendable (
        _ input: URL, _ output: URL, _ onProgress: @escaping @Sendable (Double) -> Void
      ) async throws -> String
  ) {
    self.run = run
  }

  /// The runner over the StarNet `tools` find: `StarNetError.missing` with the path looked at,
  /// or `.cannotRun` when this Mac cannot launch that binary.
  package static func located(
    by tools: HostTools, refusal: (String) -> String? = { ExecutableCheck.refusal(path: $0) }
  ) async throws -> Self {
    let status = await tools.locate(.starnet)
    guard status.isUsable else { throw StarNetError.missing(path: status.path) }
    if let reason = refusal(status.path) {
      throw StarNetError.cannotRun(path: status.path, reason: reason)
    }
    return live(binary: status.path)
  }

  /// A runner over the StarNet at `binary`, its command-line generation probed once per run.
  package static func live(binary: String) -> Self {
    Self(run: { input, output, onProgress in
      let cli = try await StarNetCLI.detect(binary: binary)
      return try await execute(
        binary, arguments: cli.arguments(input: input, output: output), output: output,
        onProgress: onProgress)
    })
  }

  /// The starless version of `image`.
  ///
  /// Written as a 16-bit TIFF into `scratch`, run, read back with the row order and metadata of
  /// `image`, so the two pair pixel for pixel. Off the caller's actor: encoding and decoding a full-size TIFF is CPU-bound.
  @concurrent
  package func starless(
    of image: sending AstroImage, in scratch: URL,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> sending AstroImage {
    try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    let input = scratch.appendingPathComponent("starnet-input.tif")
    let output = scratch.appendingPathComponent("starnet-starless.tif")
    try? FileManager.default.removeItem(at: output)
    try ImageExport.write(image, to: input, format: .tiff16)
    _ = try await run(input, output, onProgress)
    let starless = try ImageImport.read(at: output).inRowOrder(image.metadata.rowOrder)
    return AstroImage(
      width: starless.width, height: starless.height, planes: starless.planes,
      metadata: image.metadata)
  }

  private static func execute(
    _ binary: String, arguments: [String], output: URL,
    onProgress: @escaping @Sendable (Double) -> Void
  ) async throws -> String {
    var options = PlatformOptions()
    // Cancelling the task stops StarNet: SIGTERM, then SIGKILL two seconds later.
    options.teardownSequence = [.gracefulShutDown(allowedDurationToNextStep: .seconds(2))]
    let result = try await Subprocess.run(
      .path(FilePath(binary)), arguments: Arguments(arguments), platformOptions: options,
      input: .none, output: .sequence, error: .combinedWithOutput
    ) { execution in
      let progress = StarNetProgress()
      var log = Data()
      for try await buffer in execution.standardOutput {
        let chunk = Data(buffer: buffer)
        log.append(chunk)
        for percent in progress.append(chunk) { onProgress(percent) }
      }
      return String(bytes: log, encoding: .utf8) ?? ""
    }
    guard case .exited(let code) = result.terminationStatus, code == 0 else {
      let code: Int32 = if case .exited(let value) = result.terminationStatus { value } else { -1 }
      throw StarNetError.failed(exitCode: code, log: result.closureResult)
    }
    guard FileManager.default.fileExists(atPath: output.path) else {
      throw StarNetError.noOutput(path: output.path)
    }
    return result.closureResult
  }
}
