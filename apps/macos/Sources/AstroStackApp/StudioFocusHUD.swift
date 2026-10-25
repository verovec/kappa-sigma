internal import RenderKit
internal import SwiftUI

/// The full-screen image's controls (card 0127).
///
/// The zoom, Fit, 1:1, −, +, Exit and the pixel under the pointer (the View panel is hidden). It
/// fades 2 s after the pointer stops and comes back when it moves.
struct StudioFocusHUD: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale
  @State private var awake = true
  @State private var hovered = false

  var body: some View {
    let viewer = model.viewer.model
    HStack(spacing: DesignMetrics.spacingS) {
      Text(verbatim: viewer.frame.transform.zoomText(locale: locale))
        .monospacedDigit()
        .frame(minWidth: 56)
      // The same model methods as the View menu: one zoom path (card 0127).
      control("fit", .app("Zoom to Fit"), "arrow.down.right.and.arrow.up.left") {
        viewer.zoomToFit()
      }
      control("actual", .app("Actual Pixels"), "1.magnifyingglass") { viewer.zoomToActualSize() }
      control("zoomOut", .app("Zoom Out"), "minus.magnifyingglass") { viewer.zoomOut() }
      control("zoomIn", .app("Zoom In"), "plus.magnifyingglass") { viewer.zoomIn() }
      if let readout = viewer.readout {
        Divider().frame(height: 16)
        Text(verbatim: readout.summary(locale: locale)).monospacedDigit().lineLimit(1)
      }
      Divider().frame(height: 16)
      control("exit", .app("Exit Full-Screen Image"), "arrow.down.right.and.arrow.up.left.square") {
        model.toggleFocus()
      }
    }
    .padding(.horizontal, DesignMetrics.spacingM)
    .padding(.vertical, DesignMetrics.spacingS)
    .background(.regularMaterial, in: Capsule())
    .padding(DesignMetrics.spacingL)
    .opacity(awake || hovered ? 1 : 0)
    .animation(.easeInOut(duration: 0.3), value: awake || hovered)
    .onHover { hovered = $0 }
    .task(id: viewer.pointerMoves) {
      awake = true
      try? await Task.sleep(for: .seconds(2))
      if !Task.isCancelled { awake = false }
    }
  }

  private func control(
    _ name: String, _ label: LocalizedStringResource, _ symbol: String,
    action: @escaping () -> Void
  ) -> some View {
    Button(action: action) { Image(systemName: symbol) }
      .buttonStyle(.borderless)
      .help(Text(label))
      .accessible(.studioFocus(name), label: label)
  }
}
