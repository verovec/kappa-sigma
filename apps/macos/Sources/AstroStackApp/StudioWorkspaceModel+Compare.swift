internal import ImageKit
internal import ProcessKit

extension StudioWorkspaceModel {
  /// Compares the viewer's image with the output of step `index` (`nil`: no compare).
  package func compare(toStep index: Int?) throws {
    guard let index else {
      viewer.reference = nil
      comparing = nil
      comparingWith = nil
      return
    }
    // On a moved preview (a crop, a flip) the step's pixels are not under the ones shown.
    guard !showsMovedGrid else { throw UserFacingError.movedPreview }
    guard steps.indices.contains(index) else { throw HistoryError.noStep(index) }
    // A step before a crop, turn or flip is not on the head's grid (decided before any read).
    guard onHeadGrid(step: index) else { throw StudioError.otherGrid(step: index) }
    let image = try studio.output(ofStep: index, on: selection)
    // A step of another size (a host tool trimmed it) does not lie on the grid either.
    guard image.width == head.width, image.height == head.height else {
      throw StudioError.otherGrid(step: index)
    }
    viewer.reference = try Self.texture(image, device: studio.session.device)
    comparing = index
    comparingWith = nil
  }

  /// Compares with step `index`, or stops when it is the one compared; a failure is reported.
  package func toggleCompare(_ index: Int) {
    do {
      try compare(toStep: comparing == index ? nil : index)
    } catch {
      failure = UserFacingError(error).message
    }
  }
}
