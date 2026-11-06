package import Metal
package import SwiftUI

/// The viewer: the image on the GPU, the region outline over it, the panel beside it unless
/// hidden (`ViewerModel.showsPanel`).
package struct ViewerView: View {
  private let model: ViewerModel
  private let renderer: ViewerRenderer
  private let texture: ImageTexture
  private let reference: ImageTexture?
  private let mask: MTLTexture?

  /// A viewer of `model.image` already uploaded as `texture`; `reference` is what the compare
  /// key and split show (the current image when `nil`); `mask` is the process mask the overlay
  /// tints (`ViewerFrame.maskOverlay`).
  package init(
    model: ViewerModel, renderer: ViewerRenderer, texture: ImageTexture, reference: ImageTexture?,
    mask: MTLTexture? = nil
  ) {
    self.model = model
    self.renderer = renderer
    self.texture = texture
    self.reference = reference
    self.mask = mask
  }

  /// The image's column: it never collapses, the panel goes first when the room runs out.
  package static let surfaceWidth = ColumnWidth(min: 240, ideal: 480, max: .infinity)
  /// The « View » panel's column with its divider; it collapses when the image would be under
  /// its minimum (display only: `showsPanel` stays the user's choice).
  package static let panelWidth = ColumnWidth(min: 281, ideal: 281, max: 281, collapseRank: 0)

  package var body: some View {
    // The minimum never follows the content (card 0176): a split view's column is never asked for
    // more than the window gives it.
    CollapsingColumns {
      ZStack(alignment: .topLeading) {
        MetalSurface(
          model: model, renderer: renderer, texture: texture, reference: reference, mask: mask)
        RegionOutline(model: model).allowsHitTesting(false)
      }
      .overlay(alignment: .topTrailing) { PanelToggle(model: model) }
      .clipped()
      .frame(minHeight: 320)
      .column(Self.surfaceWidth)
      // The surface keeps its slot whether the panel is shown: SwiftUI keeps the same
      // `ViewerMTKView` (card 0109), so zoom, focus and the ⌥ compare key survive (card 0126).
      if model.showsPanel {
        HStack(spacing: 0) {
          Divider()
          ViewerPanel(model: model).frame(width: 280)
        }
        .column(Self.panelWidth)
      }
    }
    .onGeometryChange(for: Bool.self) { geometry in
      geometry.size.width >= Self.surfaceWidth.min + Self.panelWidth.min
    } action: { room in
      model.panelHasRoom = room
    }
  }
}

/// The canvas-edge button that hides or shows the « View » panel (⌥⌘0), so a hidden panel is
/// found again without the menu.
private struct PanelToggle: View {
  let model: ViewerModel

  var body: some View {
    let title = ViewerMTKView.panelCommandTitle(showsPanel: model.showsPanel)
    let help = ViewerMTKView.panelToggleHelp(
      showsPanel: model.showsPanel, hasRoom: model.panelHasRoom)
    Button {
      model.showsPanel.toggle()
    } label: {
      Image(systemName: "sidebar.trailing")
    }
    .buttonStyle(.borderless)
    .padding(8)
    // Without room the panel cannot show: the toggle says why instead of seeming to do nothing.
    .disabled(!model.panelHasRoom)
    .help(Text(help))
    .accessible(.viewer("togglePanel"), label: title)
  }
}

/// `ViewerMTKView` in SwiftUI.
private struct MetalSurface: NSViewRepresentable {
  let model: ViewerModel
  let renderer: ViewerRenderer
  let texture: ImageTexture
  let reference: ImageTexture?
  let mask: MTLTexture?

  func makeNSView(context: Context) -> ViewerMTKView {
    ViewerMTKView(
      model: model, renderer: renderer, texture: texture, reference: reference, mask: mask)
  }

  /// The view is kept (zoom, focus, the ⌥ compare key survive): only its inputs change.
  func updateNSView(_ view: ViewerMTKView, context: Context) {
    view.show(texture: texture, reference: reference, mask: mask)
  }
}

/// The region's outline, in points over the Metal surface.
private struct RegionOutline: View {
  let model: ViewerModel
  @Environment(\.displayScale) private var displayScale

  var body: some View {
    if let region = model.frame.region {
      let transform = model.frame.transform
      let factor = transform.scale * displayScale
      let rect = CGRect(
        x: (Double(region.x) - transform.origin.x) / factor,
        y: (Double(region.y) - transform.origin.y) / factor,
        width: Double(region.width) / factor, height: Double(region.height) / factor)
      Path { $0.addRect(rect) }
        .stroke(DesignColor.regionOutline.color, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
  }
}
