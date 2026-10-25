internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// The catalogue title of process `id` (ProcessKit's catalog key), or the id.
  package func title(of id: String) -> String {
    registry.type(id: id)?.title ?? id
  }

  /// Clears the mask (card 0111), and the refusal it caused: the row under a panel that does
  /// not take the mask offers this, the mask row's « No mask » too.
  package func clearMask() {
    mask = nil
    if failure == Self.maskRefusal { failure = nil }
  }

  /// The mask of the head, one plane, or `nil` without a mask — and for a geometric process,
  /// which moves the whole grid and has no mask row (card 0090).
  func maskImage() throws -> AstroImage? {
    // A branch takes no mask: its process reads the layer alone (card 0119).
    guard let mask, selection == .main, !(panel?.type is any GeometricProcess.Type) else {
      return nil
    }
    let device = studio.session.device
    let head = self.head
    let built = try MaskBuilder(device: device)
      .build(mask, image: GPUImage(device: device, image: head), scale: 1)
    return AstroImage(
      width: head.width, height: head.height, planes: built.read(), metadata: head.metadata)
  }
}
