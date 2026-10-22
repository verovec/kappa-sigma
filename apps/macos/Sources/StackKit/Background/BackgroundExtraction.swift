package import Foundation
package import ImageKit

/// Background extraction on one linear image (design §3.2, card 0072): the engine the user chose
/// runs with the values shown, the pair (corrected, model) comes back in ImageKit terms whichever
/// engine ran, and an identical request is served from `BackgroundCache` without a tool call.
///
/// A struct of closures: `graxpert` locates the runner on demand (a missing GraXpert fails only a
/// GraXpert request, the Siril engines stay available — never a cascade, R2).
package struct BackgroundExtraction: Sendable {
  /// The GraXpert runner, or `GraXpertError.missing`.
  package var graxpert: @Sendable () async throws -> GraXpertRunner
  /// The Siril runner for the `subsky` engines.
  package var siril: SirilRunner

  /// An extraction over the two runners.
  package init(
    graxpert: @escaping @Sendable () async throws -> GraXpertRunner, siril: SirilRunner
  ) {
    self.graxpert = graxpert
    self.siril = siril
  }

  /// The extraction locating GraXpert through `tools` at each GraXpert request.
  package static func located(by tools: HostTools, siril: SirilRunner) -> Self {
    Self(graxpert: { try await GraXpertRunner.located(by: tools) }, siril: siril)
  }

  /// The corrected image and model of `image` under `engine` and `correction`.
  ///
  /// Works under `scratch` (`background/<key>/`, the tool in a folder of its own per run so two
  /// runs of one request never share files; only the pair stays). Off the caller's actor:
  /// hashing, writing and reading a full-size FITS is CPU-bound.
  @concurrent
  package func run(
    image: sending AstroImage, engine: BackgroundEngine, correction: BackgroundCorrection,
    scratch: URL, onProgress: @escaping @Sendable (ToolProgress) -> Void
  ) async throws -> sending BackgroundResult {
    try engine.validate()
    guard engine.supports(correction) else {
      throw BackgroundExtractionError.unsupportedCorrection(engine: engine, correction: correction)
    }
    let cache = BackgroundCache(
      root: scratch.appendingPathComponent("background", isDirectory: true))
    let key = try cache.key(image: image, engine: engine, correction: correction)
    if let hit = try cache.load(key, metadata: image.metadata) {
      onProgress(ToolProgress(line: "background reused: same image and request", percent: 100))
      return hit
    }
    let folder = cache.folder(key).appendingPathComponent(
      "run-" + UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let input = folder.appendingPathComponent("input.fits")
    let output = folder.appendingPathComponent("corrected.fits")
    try FITSFile.create(image, keeping: nil, at: input)
    switch engine.tool {
    case .graxpert(let smoothing):
      let runner = try await graxpert()
      _ = try await runner.run(
        input, output, GraXpertRunner.Options(smoothing: smoothing, correction: correction),
        onProgress)
    case .siril(let subsky):
      let script = SirilScripts.backgroundExtraction(
        load: "input", out: "corrected", subsky: subsky)
      _ = try await siril.run(script, folder) { line in
        onProgress(ToolProgress(line: line.text, percent: line.percent))
      }
    }
    guard FileManager.default.fileExists(atPath: output.path) else {
      throw BackgroundExtractionError.noOutput(path: output.path)
    }
    let corrected = try BackgroundCache.read(output, metadata: image.metadata)
    let model =
      correction == .subtract ? try image.subtracting(corrected) : try image.dividing(by: corrected)
    let result = BackgroundResult(corrected: corrected, model: model, reused: false)
    try cache.store(key, result)
    return result
  }
}
