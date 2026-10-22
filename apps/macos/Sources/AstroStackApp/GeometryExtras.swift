internal import RenderKit
package import SwiftUI

/// The geometry panel's extras (card 0090): the output's size, what becomes of the plate
/// solution, and « Use region », which fills the crops from the viewer's region — disabled with
/// the reason when it cannot.
package struct GeometryExtras: View {
  let model: StudioWorkspaceModel
  let output: GeometryOutput
  @Environment(\.locale) private var locale

  /// The extras of the geometry panel of `model`, whose output is `output`.
  package init(model: StudioWorkspaceModel, output: GeometryOutput) {
    self.model = model
    self.output = output
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      let format = AstroFormat(locale: locale)
      Text(.app("Output: \(format.integer(output.width)) × \(format.integer(output.height)) px"))
      Text(Self.solution(output.wcs))
        .foregroundStyle(DesignColor.textSecondary.color)
      Button(.app("Use region")) { model.useRegion() }
        .disabled(model.regionUnavailable != nil)
        .accessible(.studioUseRegion, label: .app("Use region"))
      if let reason = model.regionUnavailable.flatMap(Self.reason) {
        Text(reason).foregroundStyle(DesignColor.textSecondary.color)
      }
    }
  }

  /// The sentence for what becomes of the plate solution.
  package static func solution(_ wcs: GeometryOutput.PlateSolution) -> LocalizedStringResource {
    switch wcs {
    case .none: .app("No plate solution.")
    case .moved: .app("The plate solution moves with the pixels.")
    case .removed:
      .app("The plate solution is removed: a frame resampled at an angle needs a new solve.")
    }
  }

  /// Why « Use region » is disabled (none for another panel: the extras are not shown).
  package static func reason(_ unavailable: RegionUnavailable) -> LocalizedStringResource? {
    switch unavailable {
    case .notGeometry: nil
    case .noRegion: .app("Draw a region in the viewer first.")
    case .previewMoved:
      .app("The viewer shows the moved preview: draw the region with every value at zero.")
    }
  }
}
