package import AppKit
internal import ProcessKit

// MARK: - Rotate and flip the shown image (card 0105)

extension ProjectDocument {
  /// Edit › Rotate 90° Clockwise (⇧⌘R): the geometry panel turns the shown image; ⌘E applies.
  @objc package func rotateImageClockwise(_ sender: Any?) {
    windowModel?.workspace?.moveGeometry(.rotateClockwise)
  }

  /// Edit › Rotate 90° Counterclockwise (⌥⇧⌘R).
  @objc package func rotateImageCounterclockwise(_ sender: Any?) {
    windowModel?.workspace?.moveGeometry(.rotateCounterclockwise)
  }

  /// Edit › Flip Horizontally (⇧⌘H): left and right of the shown image swapped.
  @objc package func flipImageHorizontally(_ sender: Any?) {
    windowModel?.workspace?.moveGeometry(.flipHorizontally)
  }

  /// Edit › Flip Vertically (⇧⌘V): top and bottom of the shown image swapped.
  @objc package func flipImageVertically(_ sender: Any?) {
    windowModel?.workspace?.moveGeometry(.flipVertically)
  }

  /// Whether the rotate and flip commands are enabled: on the Studio stage with a stack open,
  /// no pipeline moving the head, and no text being edited (⇧⌘V there is the field's own).
  package static func geometryEnabled(in window: ProjectWindowModel?) -> Bool {
    guard let window, window.selection == .studio, let workspace = window.workspace else {
      return false
    }
    return workspace.pipeline?.isRunning != true && !(NSApp.keyWindow?.firstResponder is NSText)
  }

  /// The rotate and flip commands' actions: on the Studio stage with a stack open.
  package static let geometryActions: [Selector] = [
    #selector(rotateImageClockwise(_:)), #selector(rotateImageCounterclockwise(_:)),
    #selector(flipImageHorizontally(_:)), #selector(flipImageVertically(_:)),
  ]
}
