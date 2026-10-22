package import Foundation
internal import ImageKit
package import ProcessKit
package import StackKit
internal import Synchronization

/// Background extraction's tool (card 0092): the panel's values read as StackKit's request, the
/// chosen engine run on every target `applyTo` names, the corrected layers and the model back
/// as the step's layers.
package nonisolated enum BackgroundExtractionTool {
  /// The tool over `extraction`, working in `scratch` (its pairs removed after each run: the
  /// history keeps the step's files, a cache there would only grow).
  package static func tool(extraction: BackgroundExtraction, scratch: URL) -> StudioTool {
    StudioTool { input, params, onProgress in
      let folder = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: folder) }
      // One bar for the whole run: each target's lines rescaled into its share of it.
      let targets = BackgroundExtractionProcess.targets(params, layerIDs: input.layers.keys)
      let count = max((targets.head ? 1 : 0) + targets.layers.count, 1)
      let next = Mutex(0)
      let extract: BackgroundExtractionProcess.Extract = { image, params, _ in
        let index = next.withLock { value in
          defer { value += 1 }
          return value
        }
        // A copy of its own: the engine works on it off the main actor.
        let copy = AstroImage(
          width: image.width, height: image.height, planes: image.planes,
          metadata: image.metadata)
        let result = try await extraction.run(
          image: copy, engine: BackgroundEngine(params: params),
          correction: BackgroundCorrection(params: params), scratch: folder
        ) { line in
          onProgress(
            ToolProgress(
              line: line.line, percent: line.percent.map { (index * 100 + $0) / count }))
        }
        return (result.corrected, result.model)
      }
      let output = try await BackgroundExtractionProcess.run(
        input, params: params, extract: extract)
      return StudioToolResult(
        image: output.result, report: nil, outputs: output.outputs, replaced: output.replaced)
    }
  }

  /// The tool over the installed GraXpert and Siril, each located at its own run (a missing
  /// one fails only its engines, never another engine instead, R2).
  package static func live(scratch: URL, hostTools: HostTools = .live()) -> StudioTool {
    let siril = SirilRunner { script, directory, onLine in
      try await SirilRunner.live(binary: SirilTool.locate()).run(script, directory, onLine)
    }
    return tool(
      extraction: BackgroundExtraction.located(by: hostTools, siril: siril), scratch: scratch)
  }

  /// The tool the process `processID` needs with `params` (`nil`: not background extraction).
  package static func host(for processID: String, params: ParamSet) -> HostTool? {
    guard processID == BackgroundExtractionProcess.id else { return nil }
    return host(engine: params.choice("engine"))
  }

  /// The tool behind an engine option: the one the run uses (`BackgroundEngine(params:)`).
  package static func host(engine: String) -> HostTool {
    BackgroundEngine.usesGraXpert(engine: engine) ? .graxpert : .siril
  }
}

extension BackgroundEngine {
  /// Whether the engine option `engine` runs GraXpert: every option but the Siril ones, as
  /// `init(params:)` reads it.
  nonisolated package static func usesGraXpert(engine: String) -> Bool {
    engine != "siril-rbf" && engine != "siril-polynomial"
  }

  /// The engine and values of background extraction's `params`, as shown (whole numbers
  /// rounded, never clamped: the engine refuses what its tool would).
  nonisolated package init(params: ParamSet) {
    switch params.choice("engine") {
    case "siril-rbf":
      self = .sirilRBF(
        smooth: params.number("rbfSmooth"), samples: Int(params.number("samples").rounded()),
        tolerance: params.number("tolerance"), dither: params.flag("dither"))
    case "siril-polynomial":
      self = .sirilPolynomial(degree: Int(params.number("degree").rounded()))
    default:
      self = .graxpert(smoothing: params.number("smoothing"))
    }
  }
}

extension BackgroundCorrection {
  /// Subtract or divide, as background extraction's `params` say.
  nonisolated package init(params: ParamSet) {
    self = params.choice("correction") == "divide" ? .divide : .subtract
  }
}
