internal import Foundation
internal import ProcessKit
internal import StackKit

extension UserFacingError {
  /// What a Studio failure means to the user, in their words (card 0087).
  static func message(_ error: StudioError) -> LocalizedStringResource {
    switch error {
    case .unknownProcess(let id): .app("The Studio has no process “\(id)”.")
    case .emptyBundle: .app("This stack has no layer to start the Studio from.")
    case .needsTool(let id): .app("“\(id)” runs a host tool: nothing was applied without it.")
    }
  }

  /// Why a plate solve gave nothing (card 0093).
  static func message(_ error: PlateSolveError) -> LocalizedStringResource {
    switch error {
    case .failed(let reason):
      .app("Siril found no solution: \(reason). Check the centre, focal length and pixel size.")
    case .catalogueMissing(let path):
      .app("No local star catalogue at \(path): run just download-catalogues, or go online.")
    case .noSolution(let path): .app("Siril reported a solution but wrote none in \(path).")
    }
  }

  /// Why the plate-solve values cannot be solved with (card 0093).
  static func message(_ error: PlateSolveTool.InputError) -> LocalizedStringResource {
    switch error {
    case .coordinatesMissing:
      .app("Give the image centre (right ascension and declination), or take the header's.")
    case .unreadable(let text):
      .app("“\(text)” is not a coordinate: write 00 42 44 and +41 16 09, or degrees.")
    case .opticsMissing: .app("Give the focal length and the pixel size, or take the header's.")
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
