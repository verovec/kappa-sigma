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

  /// A result of `image` with `report`.
  package init(image: AstroImage, report: (@Sendable (Locale) -> LocalizedStringResource)?) {
    self.image = image
    self.report = report
  }
}

/// The Apply of a host-tool process (`ImageProcess.hostTool`).
///
/// The head, the panel's values and a progress sink → the step. Injected into the Studio, so tests run fakes and the app runs
/// Siril; a process without its tool is never recorded from its preview.
package nonisolated struct StudioTool: Sendable {
  /// Runs the tool.
  package let run:
    @Sendable (
      sending AstroImage, ParamSet, @escaping @Sendable (ToolProgress) -> Void
    ) async throws -> sending StudioToolResult

  /// A tool running `run`.
  package init(
    run:
      @escaping @Sendable (
        sending AstroImage, ParamSet, @escaping @Sendable (ToolProgress) -> Void
      ) async throws -> sending StudioToolResult
  ) {
    self.run = run
  }

  /// The tools the app ships whose host tool is installed, by process id, working under
  /// `scratch`; a process without its tool is greyed in the catalogue (never another tool, R2).
  package static func standard(
    scratch: URL,
    sirilInstalled: Bool = FileManager.default.isExecutableFile(atPath: SirilTool.path())
  ) -> [String: Self] {
    sirilInstalled ? [PlateSolveProcess.id: PlateSolveTool.live(scratch: scratch)] : [:]
  }

  /// The same tool for a pipeline step (`PipelineRunner`): one definition for both.
  package func batchProcess(schema: ParamSchema) -> PipelineRunner.BatchProcess {
    let run = self.run
    return PipelineRunner.BatchProcess(schema: schema) { image, params, progress in
      let copy = AstroImage(
        width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
      return try await run(copy, params) { line in
        if let percent = line.percent { progress(Double(percent) / 100) }
      }.image
    }
  }
}
