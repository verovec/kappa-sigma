internal import Foundation
internal import ProcessKit

extension UserFacingError {
  /// What a Studio failure means to the user, in their words (card 0087).
  static func message(_ error: StudioError) -> LocalizedStringResource {
    switch error {
    case .unknownProcess(let id): .app("The Studio has no process “\(id)”.")
    case .emptyBundle: .app("This stack has no layer to start the Studio from.")
    case .otherSize(let step):
      .app("Step \(step + 1) has another size than the image: it cannot be compared.")
    case .movedPreview:
      .app("The preview moves the pixels: compare once the geometry is applied or reset.")
    }
  }

  /// What a history failure means to the user (card 0087).
  static func message(_ error: HistoryError) -> LocalizedStringResource {
    switch error {
    case .noStep(let index): .app("Step \(index + 1) of the history no longer exists.")
    case .nothingToUndo: .app("There is nothing to undo.")
    case .nothingToRedo: .app("There is nothing to redo.")
    case .unknownSnapshot(let name): .app("No snapshot is named “\(name)”.")
    case .duplicateSnapshot(let name): .app("A snapshot is already named “\(name)”.")
    case .unreadable(let why): .app("This stack's Studio history cannot be read back: \(why).")
    }
  }
}
