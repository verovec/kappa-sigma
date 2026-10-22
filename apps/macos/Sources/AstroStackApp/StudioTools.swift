package import Foundation
internal import ImageKit
package import ProcessKit
package import StackKit

/// The host tools behind the Studio's batch processes (card 0092).
///
/// Where each tool stands, and the background extraction they run: a struct of closures, so
/// tests give a missing GraXpert and a fake engine.
package struct StudioTools: Sendable {
  /// The status of a tool, probed now.
  package var locate: @Sendable (HostTool) async -> ToolStatus
  /// Corrected image and model of one image (StackKit `BackgroundExtraction`).
  package var background: BackgroundExtractionProcess.Extract
  /// The folder the extraction works and caches in, removed with the workspace (`nil`: none).
  package var scratch: URL?

  /// Tools answering with `locate` and extracting with `background` in `scratch`.
  package init(
    locate: @escaping @Sendable (HostTool) async -> ToolStatus, scratch: URL? = nil,
    background: @escaping BackgroundExtractionProcess.Extract
  ) {
    self.locate = locate
    self.background = background
    self.scratch = scratch
  }

  /// The installed tools, working under `scratch`.
  ///
  /// The extraction's work files and cache go to `scratch` (a temporary folder, never the
  /// project package nor `output/`). Siril is located at each Siril run, so a missing Siril fails only a Siril
  /// engine.
  package static func live(scratch: URL, hostTools: HostTools = .live()) -> Self {
    let siril = SirilRunner { script, directory, onLine in
      try await SirilRunner.live(binary: SirilTool.locate()).run(script, directory, onLine)
    }
    let extraction = BackgroundExtraction.located(by: hostTools, siril: siril)
    return Self(locate: hostTools.locate, scratch: scratch) { image, params, progress in
      // A copy of its own: the engine works on it off the main actor.
      let input = AstroImage(
        width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
      let result = try await extraction.run(
        image: input, engine: BackgroundEngine(params: params),
        correction: BackgroundCorrection(params: params), scratch: scratch
      ) { line in
        if let percent = line.percent { progress(Double(percent) / 100) }
      }
      return (result.corrected, result.model)
    }
  }

  /// The tool the batch process `processID` needs with `params` (`nil`: a GPU process).
  package static func tool(for processID: String, params: ParamSet) -> HostTool? {
    guard processID == BackgroundExtractionProcess.id else { return nil }
    return tool(engine: params.choice("engine"))
  }

  /// The tool behind an engine option of background extraction: the one the run uses
  /// (`BackgroundEngine(params:)`).
  package static func tool(engine: String) -> HostTool {
    BackgroundEngine.usesGraXpert(engine: engine) ? .graxpert : .siril
  }
}

extension BackgroundEngine {
  /// Whether the engine option `engine` runs GraXpert: every option but the Siril ones, as
  /// `init(params:)` reads it.
  package static func usesGraXpert(engine: String) -> Bool {
    engine != "siril-rbf" && engine != "siril-polynomial"
  }

  /// The engine and values of background extraction's `params`, as shown (whole numbers
  /// rounded, never clamped: the engine refuses what its tool would).
  package init(params: ParamSet) {
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
  package init(params: ParamSet) {
    self = params.choice("correction") == "divide" ? .divide : .subtract
  }
}
