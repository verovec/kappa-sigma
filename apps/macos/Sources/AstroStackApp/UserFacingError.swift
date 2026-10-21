package import Foundation
package import StackKit

/// An error as the user reads it: one catalog sentence naming what to act on (the path, the
/// command, the value), never the raw `"\(error)"` of a Swift enum.
package nonisolated enum UserFacingError: LocalizedError, Equatable {
  case siril(SirilError)
  case inspect(InspectError)
  case calibration(CalibrationError)
  case preprocess(PreprocessError)
  /// The document was closed under an open sheet.
  case projectClosed
  /// An error without a sentence of its own (SQLite, FITS, the file system): its description,
  /// which names the file or value it is about.
  case other(String)

  /// The kit error `error` wraps, or the system's own description of it.
  package init(_ error: any Error) {
    switch error {
    case let error as Self: self = error
    case let error as SirilError: self = .siril(error)
    case let error as InspectError: self = .inspect(error)
    case let error as CalibrationError: self = .calibration(error)
    case let error as PreprocessError: self = .preprocess(error)
    case let error as LocalizedError where error.errorDescription != nil:
      self = .other(error.errorDescription ?? "")
    // A system error has a sentence of its own; a Swift error without one would read
    // "…ImageKit.FITSFileError error 1.", hiding the path or card it carries.
    case let error where type(of: error) is NSError.Type: self = .other(error.localizedDescription)
    default: self = .other(String(describing: error))
    }
  }

  /// The sentence, in the user's languages unless the resource's locale is set.
  package var message: LocalizedStringResource {
    switch self {
    case .siril(let error): Self.message(error)
    case .inspect(let error): Self.message(error)
    case .calibration(let error): Self.message(error)
    case .preprocess(let error): Self.message(error)
    case .projectClosed: .app("This project is not open any more; reopen it and import again.")
    case .other(let description): .app("\(description)")
    }
  }

  package var errorDescription: String? { String(localized: message) }

  // MARK: - Sentences

  private static func message(_ error: SirilError) -> LocalizedStringResource {
    switch error {
    case .notInstalled(let path):
      .app("Siril is not installed at \(path). Install Siril 1.4 or later, then try again.")
    case .notSiril(let output):
      .app("The program at the Siril path is not Siril (it answered: \(output)).")
    case .unreadableVersion(let output):
      .app("Siril did not report its version (it answered: \(output)).")
    case .tooOld(let version):
      .app("Siril \(version) is too old: AstroStack needs Siril 1.4 or later.")
    case .scriptFailed(let exitCode, let hint):
      .app("A Siril script failed (exit code \(Int(exitCode))): \(hint)")
    case .commandFailed(let command, let hint): .app("Siril refused “\(command)”: \(hint)")
    case .restarted(let command):
      .app("Siril stopped during “\(command)” and was restarted; run the step again.")
    case .sessionFailed(let reason): .app("Siril could not start: \(reason)")
    }
  }

  private static func message(_ error: InspectError) -> LocalizedStringResource {
    switch error {
    case .unknownFilterSet(let value):
      .app("“\(value)” is not a filter set: use unknown, broadband or dualband.")
    case .unknownColorChoice(let value):
      .app("“\(value)” is not a colour model: use auto, mono or osc.")
    case .noLightsForColorModel(let model, let count):
      .app("No light frame matches the colour model \(model) (\(count) dropped): choose another.")
    case .unreadableFolder(let path):
      .app("The folder \(path) cannot be read: check that it exists and AstroStack can open it.")
    case .noFolders: .app("Choose a capture folder first.")
    }
  }

  private static func message(_ error: CalibrationError) -> LocalizedStringResource {
    switch error {
    case .unreadableLibrary(let path): .app("The calibration library \(path) cannot be read.")
    case .notAMaster(let path): .app("\(path) is not a calibration master: its name says nothing.")
    case .wouldReplace(let path, _): .app("Rebuilding would replace the library master \(path).")
    case .unreadableMaster(let path): .app("The master \(path) cannot be measured.")
    case .masterFailed(let name, let reason):
      .app("Siril could not build the master \(name): \(reason)")
    }
  }

  private static func message(_ error: PreprocessError) -> LocalizedStringResource {
    switch error {
    case .belowStackMinimum(let survivors, let registered):
      .app("Only \(survivors) of \(registered) frames survived grading: Siril needs two to stack.")
    case .mixedDimensions(let layers):
      .app("The stacked layers have different sizes: \(layers.joined(separator: ", ")).")
    case .targetBusy(let path):
      .app("Another run is already writing \(path): wait for it or cancel it.")
    case .noChannels(let errors):
      .app("No channel could be stacked: \(errors.joined(separator: "; "))")
    case .mixedColorModel:
      .app("Mono and colour lights are mixed: exclude one kind on the Import sheet, then rerun.")
    }
  }
}
