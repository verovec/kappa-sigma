package import AppKit
internal import ProcessKit

// MARK: - Rotate and flip the shown image (card 0105)

extension ProjectDocument {
  /// Edit › Rotate 90° Clockwise (⇧⌘R): the geometry panel turns the shown image; ⌘E applies.
  @objc package func rotateImageClockwise(_ sender: Any?) {
    move(.rotateClockwise)
  }

  /// Edit › Rotate 90° Counterclockwise (⌥⇧⌘R).
  @objc package func rotateImageCounterclockwise(_ sender: Any?) {
    move(.rotateCounterclockwise)
  }

  /// Edit › Flip Horizontally (⇧⌘H): left and right of the shown image swapped.
  @objc package func flipImageHorizontally(_ sender: Any?) {
    move(.flipHorizontally)
  }

  /// Edit › Flip Vertically (⇧⌘V): top and bottom of the shown image swapped.
  @objc package func flipImageVertically(_ sender: Any?) {
    move(.flipVertically)
  }

  /// Whether the rotate and flip commands are enabled: on the Studio stage with a stack open,
  /// no pipeline moving the head, no text being edited (⇧⌘V there is the field's own, and a
  /// field committing later would overwrite the move) and no other panel's edits to replace.
  package static func geometryEnabled(in window: ProjectWindowModel?) -> Bool {
    guard let window, window.selection == .studio, let workspace = window.workspace else {
      return false
    }
    return workspace.pipeline?.isRunning != true && workspace.canMoveGeometry
      && !(NSApp.keyWindow?.firstResponder is NSText)
  }

  /// `move` on the workspace, when the menu would allow it (an action sent without validation
  /// does no more).
  private func move(_ move: GeometryMove) {
    guard Self.geometryEnabled(in: windowModel) else { return }
    windowModel?.workspace?.moveGeometry(move)
  }

  /// The rotate and flip commands' actions: on the Studio stage with a stack open.
  package static let geometryActions: [Selector] = [
    #selector(rotateImageClockwise(_:)), #selector(rotateImageCounterclockwise(_:)),
    #selector(flipImageHorizontally(_:)), #selector(flipImageVertically(_:)),
  ]
}
