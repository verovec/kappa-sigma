internal import RenderKit
package import SwiftUI

/// The mask under a panel that does not take it (card 0111).
///
/// A mask set for an earlier process stays on, so the row names it, says what it does here, and
/// offers Clear — never reset behind the user's back (R2). Shown only while a mask is set.
package struct StudioInactiveMaskRow: View {
  let model: StudioWorkspaceModel
  /// Geometry ignores the mask; a host tool refuses to run under it.
  let geometry: Bool

  package var body: some View {
    if let mask = model.mask {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
        Label {
          Text(Self.note(geometry: geometry, source: StudioMaskRow.Source(mask).title))
        } icon: {
          Image(systemName: geometry ? "info.circle" : "exclamationmark.triangle")
        }
        .foregroundStyle(
          geometry ? DesignColor.textSecondary.color : DesignColor.statusAttention.color)
        Button(.app("Clear Mask")) { model.clearMask() }
          .accessible(.studioMaskClear, label: .app("Clear Mask"))
      }
    }
  }

  /// What the mask does under this panel: ignored by geometry, blocking a host tool's Apply.
  package static func note(geometry: Bool, source: LocalizedStringResource)
    -> LocalizedStringResource
  {
    geometry
      ? .app("Mask active: \(source), ignored by this process: it moves the whole image.")
      : .app(
        "Mask active: \(source), not used by this process; Apply is blocked until it is cleared.")
  }
}
