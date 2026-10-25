package import ProcessKit
internal import RenderKit
package import SwiftUI

/// The mask under a panel that does not take it (card 0111).
///
/// A mask set for an earlier process stays on, so the row names it, says what it does here, and
/// offers Clear — never reset behind the user's back (R2). Shown only while a mask is set.
package struct StudioInactiveMaskRow: View {
  /// What a panel does with a mask it does not take.
  package enum Kind: Equatable, Sendable {
    /// Geometry moves the whole grid: the mask is ignored.
    case ignored
    /// A host tool works on the whole image: Apply is blocked while a mask is set.
    case blocking
    /// On a branch (card 0119): the process reads its layer alone, under no mask.
    case branch
  }

  let model: StudioWorkspaceModel
  let kind: Kind

  package var body: some View {
    if let mask = model.mask {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
        StatusBadge(
          kind == .ignored ? .unavailable : .attention,
          Self.note(kind, source: Self.name(mask)))
        Button(.app("Clear Mask")) { model.clearMask() }
          .accessible(.studioMaskClear, label: .app("Clear Mask"))
      }
    }
  }

  /// The row a panel of `type` with `params` shows instead of the mask row, `nil` for a process
  /// that takes the mask.
  package static func kind(for type: any ImageProcess.Type, params: ParamSet) -> Kind? {
    if type is any GeometricProcess.Type { return .ignored }
    return type.runsTool(params) ? .blocking : nil
  }

  /// What the mask does under this panel: ignored by geometry, blocking a host tool's Apply.
  package static func note(_ kind: Kind, source: LocalizedStringResource)
    -> LocalizedStringResource
  {
    switch kind {
    case .ignored:
      .app("Mask active: \(source), ignored by this process: it moves the whole image.")
    case .blocking:
      .app(
        "Mask active: \(source), not used by this process; Apply is blocked until it is cleared.")
    case .branch:
      .app("Mask active: \(source), not used on a branch: the process reads the layer alone.")
    }
  }

  /// The mask as set: its source, and « inverted » when it is (R2: every setting visible).
  static func name(_ mask: Mask) -> LocalizedStringResource {
    let title = StudioMaskRow.Source(mask).title
    return mask.inverted ? .app("\(title), inverted") : title
  }
}
