package import Foundation
internal import ImageKit
package import ProcessKit
package import RenderKit
package import StackKit

/// StarNet as the Studio's batch process `starnet` (card 0091): the head goes through a 16-bit
/// TIFF in a scratch folder, StarNet's starless comes back as the step's `starless` layer and the
/// head stays as it was (star recomposition reads both).
nonisolated package enum StarSeparation {
  /// The step's process id, in the history and the project.
  package static let id = "starnet"
  /// StarNet takes no value of ours: its model and stride are the user's install.
  package static let schema = ParamSchema([])

  /// The history's title of the host-tool step `id` in `locale` (`nil`: not one).
  package static func title(of id: String, locale: Locale? = nil) -> LocalizedStringResource? {
    id == Self.id ? .app("Star separation (StarNet)", locale: locale) : nil
  }

  /// The install card's re-check: StarNet located and runnable on this Mac (an Intel build
  /// without Rosetta stays refused), as the separation itself would find it.
  package static func check(_ tools: HostTools)
    -> @Sendable @concurrent () async -> InstallCardModel.State
  {
    { @concurrent in
      let status = await tools.locate(.starnet)
      guard status.isUsable, ExecutableCheck.refusal(path: status.path) == nil,
        (try? await StarNetCLI.detect(binary: status.path)) != nil
      else { return .missing }
      return .found(URL(fileURLWithPath: status.path))
    }
  }

  /// The batch process over `runner`, its files in `scratch` (removed when it ends, whatever
  /// happened: a 22 Mpx TIFF pair is ~260 MB); StarNet's percentages as 0…1.
  package static func process(_ runner: StarNetRunner, scratch: URL)
    -> PipelineRunner.BatchProcess
  {
    PipelineRunner.BatchProcess(schema: schema, writes: .starless) { image, _, progress in
      // A folder per run: StarNet's file names are fixed, two windows may separate at once.
      let scratch = scratch.appendingPathComponent(UUID().uuidString, isDirectory: true)
      defer { try? FileManager.default.removeItem(at: scratch) }
      // A copy of its own crosses to StarNet's task: the caller keeps the head.
      let input = AstroImage(
        width: image.width, height: image.height, planes: image.planes, metadata: image.metadata)
      return try await runner.starless(of: input, in: scratch) { progress($0 / 100) }
    }
  }
}
