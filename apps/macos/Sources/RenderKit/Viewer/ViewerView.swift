package import SwiftUI

/// The viewer: the image on the GPU, the region outline over it, the panel beside it.
package struct ViewerView: View {
  private let model: ViewerModel
  private let renderer: ViewerRenderer
  private let texture: ImageTexture
  private let reference: ImageTexture?

  /// A viewer of `model.image` already uploaded as `texture`; `reference` is what the compare
  /// key and split show (the current image when `nil`).
  package init(
    model: ViewerModel, renderer: ViewerRenderer, texture: ImageTexture, reference: ImageTexture?
  ) {
    self.model = model
    self.renderer = renderer
    self.texture = texture
    self.reference = reference
  }

  package var body: some View {
    HStack(spacing: 0) {
      ZStack(alignment: .topLeading) {
        MetalSurface(model: model, renderer: renderer, texture: texture, reference: reference)
        RegionOutline(model: model).allowsHitTesting(false)
      }
      .clipped()
      .frame(minWidth: 480, minHeight: 320)
      Divider()
      ViewerPanel(model: model).frame(width: 280)
    }
  }
}

/// `ViewerMTKView` in SwiftUI.
private struct MetalSurface: NSViewRepresentable {
  let model: ViewerModel
  let renderer: ViewerRenderer
  let texture: ImageTexture
  let reference: ImageTexture?

  func makeNSView(context: Context) -> ViewerMTKView {
    ViewerMTKView(model: model, renderer: renderer, texture: texture, reference: reference)
  }

  func updateNSView(_ view: ViewerMTKView, context: Context) {}
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
        .stroke(Color.yellow, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    }
  }
}
