package import RenderKit
package import SwiftUI

/// The Studio (card 0087, design §5 B): the pipeline and the catalogue, the working image (the history's head,
/// or the preview of the panel's values), the panel and the history.
package struct StudioWorkspaceView: View {
  let model: StudioWorkspaceModel

  /// The Studio of `model`.
  package init(model: StudioWorkspaceModel) {
    self.model = model
  }

  /// The pipeline and catalogue column, with its divider.
  package static let leftWidth = ColumnWidth(min: 201, ideal: 261, max: 261)
  /// The image, its « View » panel inside (it collapses first).
  package static let viewerWidth = ColumnWidth(
    min: ViewerView.surfaceWidth.min, ideal: 761, max: .infinity)
  /// The panel and history column, with its divider.
  package static let sideWidth = ColumnWidth(min: 261, ideal: 321, max: 321)

  package var body: some View {
    // Columns from the width alone (card 0176): the Studio fits the detail column at the window
    // minimum, the side columns at their minimum, the View panel collapsed.
    CollapsingColumns {
      // Focused (card 0127), only the image: the viewer keeps its slot, so SwiftUI keeps the
      // same surface (card 0109) and the zoom survives.
      if !model.isFocused {
        HStack(spacing: 0) {
          leftColumn
          Divider()
        }
        .column(Self.leftWidth)
      }
      ViewerView(
        model: model.viewer.model, renderer: model.viewer.renderer,
        texture: model.viewer.texture, reference: model.viewer.reference
      )
      .overlay(alignment: .bottom) {
        if model.isFocused { StudioFocusHUD(model: model) }
      }
      .column(Self.viewerWidth)
      if !model.isFocused {
        HStack(spacing: 0) {
          Divider()
          StudioSideView(model: model)
        }
        .column(Self.sideWidth)
      }
    }
  }

  private var leftColumn: some View {
    VStack(spacing: 0) {
      // Which history the column works on (card 0119), only when there is a choice.
      if !model.selections.isEmpty {
        StudioChannelSwitcher(model: model)
        Divider()
      }
      // The pipeline on top of the left column (card 0088), the catalogue under it.
      if let pipeline = model.pipeline {
        ScrollView { PipelineSidebarView(model: pipeline) }
          .frame(maxHeight: 320)
          .fixedSize(horizontal: false, vertical: true)
        Divider()
      }
      StudioCatalogueView(model: model)
    }
  }
}
