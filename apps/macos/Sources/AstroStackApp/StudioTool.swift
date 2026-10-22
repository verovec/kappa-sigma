package import Foundation
package import ImageKit
package import ProcessKit
package import StackKit

/// What a host tool made of the head (card 0093): the step's image, and what the panel says of
/// the run.
package nonisolated struct StudioToolResult {
  /// The step's output.
  package let image: AstroImage
  /// The tool's report (a plate solution) in a locale, shown under the panel.
  package let report: (@Sendable (Locale) -> LocalizedStringResource)?
  /// New layers the step wrote, by role (a background model, card 0092).
  package let outputs: [LayerRole: AstroImage]
  /// Bundle layers the step rewrote, by id (a background-extracted Hα).
  package let replaced: [String: AstroImage]

  /// A result of `image` with `report`, the layers it wrote (`outputs`) and rewrote
  /// (`replaced`).
  package init(
    image: AstroImage, report: (@Sendable (Locale) -> LocalizedStringResource)?,
    outputs: [LayerRole: AstroImage] = [:], replaced: [String: AstroImage] = [:]
  ) {
    self.image = image
    self.report = report
    self.outputs = outputs
    self.replaced = replaced
  }
}

/// The Apply of a host-tool process (`ImageProcess.hostTool`).
///
/// The head and the bundle's layers as the steps left them, the panel's values and a progress
/// sink → the step. Injected into the Studio, so tests run fakes and the app runs Siril or
/// GraXpert; a process without its tool is never recorded from its preview.
package nonisolated struct StudioTool: Sendable {
  /// Runs the tool on the head and the layers (card 0092: background extraction reads the
  /// line layers).
  package let step:
    @Sendable (
      sending PipelineRunner.BatchInput, ParamSet, @escaping @Sendable (ToolProgress) -> Void
    ) async throws -> sending StudioToolResult

  /// A tool running `step`.
  package init(
    step:
      @escaping @Sendable (
        sending PipelineRunner.BatchInput, ParamSet, @escaping @Sendable (ToolProgress) -> Void
      ) async throws -> sending StudioToolResult
  ) {
    self.step = step
  }

  /// A tool running `run` on the head alone (plate solving).
  package init(
    run:
      @escaping @Sendable (
        sending AstroImage, ParamSet, @escaping @Sendable (ToolProgress) -> Void
      ) async throws -> sending StudioToolResult
  ) {
    self.init { input, params, onProgress in
      let image = input.image
      return try await run(
        AstroImage(
          width: image.width, height: image.height, planes: image.planes,
          metadata: image.metadata),
        params, onProgress)
    }
  }

  /// The tools the app ships whose host tool is installed, by process id, working under
  /// `scratch`; a process without its tool is greyed in the catalogue (never another tool, R2).
  package static func standard(
    scratch: URL,
    sirilInstalled: Bool = FileManager.default.isExecutableFile(atPath: SirilTool.path())
  ) -> [String: Self] {
    guard sirilInstalled else { return [:] }
    return [
      PlateSolveProcess.id: PlateSolveTool.live(scratch: scratch),
      ColourCalibrationProcess.id: ColourCalibrationTool.live(scratch: scratch),
    ]
  }
}
