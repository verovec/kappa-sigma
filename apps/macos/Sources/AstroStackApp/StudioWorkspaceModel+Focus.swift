internal import RenderKit

/// Card 0127: the full-screen image — only the viewer, the columns hidden (display only, R2:
/// nothing is applied, measured or moved in the history).
extension StudioWorkspaceModel {
  /// The Studio shows only the image: no catalogue, View panel, side column or journey sidebar.
  package var isFocused: Bool { viewer.model.isFocused }

  /// Enters or leaves the focus (⇧⌘F, the HUD's Exit, Esc on the surface).
  package func toggleFocus() {
    viewer.model.isFocused.toggle()
  }
}
