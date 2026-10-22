internal import ImageKit
internal import ProcessKit
internal import RenderKit

extension StudioWorkspaceModel {
  /// The catalogue title of process `id` (ProcessKit's catalog key), or the id.
  package func title(of id: String) -> String {
    registry.type(id: id)?.title ?? id
  }

  /// The mask of the head, one plane, or `nil` without a mask — and for a geometric process,
  /// which moves the whole grid and has no mask row (card 0090).
  func maskImage() throws -> AstroImage? {
    guard let mask, !(panel?.type is any GeometricProcess.Type) else { return nil }
    let device = studio.session.device
    let head = studio.head
    let built = try MaskBuilder(device: device)
      .build(mask, image: GPUImage(device: device, image: head), scale: 1)
    return AstroImage(
      width: head.width, height: head.height, planes: built.read(), metadata: head.metadata)
  }
}
