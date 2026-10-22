internal import ImageKit
internal import ProcessKit

extension StudioWorkspaceModel {
  /// Compares the viewer's image with the output of step `index` (`nil`: no compare).
  package func compare(toStep index: Int?) throws {
    guard let index else {
      viewer.reference = nil
      comparing = nil
      return
    }
    let image = try studio.session.history.output(ofStep: index)
    viewer.reference = try Self.texture(image, device: studio.session.device)
    comparing = index
  }

  /// Compares with step `index`, or stops when it is the one compared; a step whose output
  /// cannot be read is reported.
  package func toggleCompare(_ index: Int) {
    do {
      try compare(toStep: comparing == index ? nil : index)
    } catch {
      failure = UserFacingError(error).message
    }
  }
}
