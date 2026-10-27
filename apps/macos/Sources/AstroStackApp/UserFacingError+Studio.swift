internal import Foundation
internal import ProcessKit
internal import StackKit

extension UserFacingError {
  /// What a Studio failure means to the user, in their words (card 0087).
  static func message(_ error: StudioError) -> LocalizedStringResource {
    switch error {
    case .unknownProcess(let id): .app("The Studio has no process “\(id)”.")
    case .emptyBundle: .app("This stack has no layer to start the Studio from.")
    case .otherGrid(let step):
      .app("Step \(step + 1) is from before a crop, turn or flip: it cannot be compared.")
    case .needsTool(let id): .app("“\(id)” runs a host tool: nothing was applied without it.")
    case .notBranchable(let id, .movesPixels):
      .app("“\(id)” moves the pixels: crop, turn or flip in the main history.")
    case .notBranchable(let id, .notPerLayer):
      .app("“\(id)” works on the whole image: apply it in the main history.")
    case .notBranchable(let id, .needsColour):
      .app("“\(id)” needs a colour layer: a line layer has a single plane.")
    }
  }

  /// Why a pipeline run stopped (step numbers from 1, as the column shows them).
  static func message(_ error: PipelineError) -> LocalizedStringResource {
    switch error {
    case .unknownProcess(let id):
      .app("The pipeline names a process the Studio does not have: “\(id)”.")
    case .noStep(let index): .app("The pipeline has no step \(index + 1).")
    case .notAtBreakpoint(let step, _):
      .app(
        "The history is not at step \(step + 1)'s breakpoint: Continue would misplace it."
      )
    case .invalidValues(let step, let ids):
      .app("Step \(step + 1) has values its process refuses: \(ids.joined(separator: ", ")).")
    case .toolMissing(let id):
      .app("Step “\(id)” runs a host tool: apply it in the Studio, then continue.")
    }
  }

  /// Why a plate solve gave nothing (card 0093).
  static func message(_ error: PlateSolveError) -> LocalizedStringResource {
    switch error {
    case .failed(let reason):
      .app("Siril found no solution: \(reason). Check the centre, focal length and pixel size.")
    case .catalogueMissing(let path):
      .app("No local star catalogue at \(path): run just download-catalogues, or go online.")
    case .noReport(let lines, let log):
      .app("Siril ended without a solution. Its last lines: \(lines). Its log: \(log)")
    case .reportUnread(let log):
      .app("Siril says it solved, but its centre, scale or rotation could not be read: \(log)")
    case .noFile(let log): .app("Siril reported a solution but wrote no file. Its log: \(log)")
    case .unreadableFile(let log):
      .app("Siril wrote a solution file that cannot be read. Its log: \(log)")
    case .noSolution(let log):
      .app("Siril wrote a file without a readable plate solution. Its log: \(log)")
    }
  }

  /// Why colour calibration gave nothing (card 0094): the manual route is named, never taken.
  static func message(_ error: ColourCalibrationError) -> LocalizedStringResource {
    switch error {
    case .unsolved:
      .app("Solve the image first (plate solving): colour calibration reads its solution.")
    case .unknownName(let kind, let name):
      switch kind {
      case .sensor, .monoSensor:
        .app("Siril does not know the sensor “\(name)”: choose one from the list.")
      case .filter, .redFilter, .greenFilter, .blueFilter:
        .app("Siril does not know the filter “\(name)”: choose one from the list.")
      case .whiteReference:
        .app("Siril does not know the white reference “\(name)”: choose one from the list.")
      }
    case .catalogueMissing(let path):
      .app("No local Gaia catalogue at \(path): run just download-catalogues, or go online.")
    case .failed(let reason):
      .app("Siril could not calibrate: \(reason). Colour balance is the manual route.")
    case .noOutput(let path): .app("Siril reported a calibration but wrote none in \(path).")
    case .noFactors: .app("Siril printed no white-balance factors: nothing was recorded.")
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
    case .movedDuring(let id):
      .app("The history moved while “\(id)” ran: its result was not recorded, run it again.")
    }
  }
}
