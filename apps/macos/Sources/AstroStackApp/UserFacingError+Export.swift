internal import Foundation
internal import ProcessKit
internal import StackKit

extension UserFacingError {
  /// What a StarNet failure means to the user (card 0091).
  static func message(_ error: StarNetError) -> LocalizedStringResource {
    switch error {
    case .missing(let path):
      .app("StarNet is not installed at \(path). Install StarNet2, then re-check.")
    case .cannotRun(let path, let reason):
      .app("This Mac cannot run the StarNet at \(path): \(reason).")
    case .probeTimedOut(let path):
      .app("The StarNet at \(path) did not answer in time; its command line is unknown.")
    case .failed(let code, let log):
      .app("StarNet stopped with code \(code): \(lastLine(log))")
    case .noOutput(let path): .app("StarNet ended without writing \(path).")
    }
  }

  /// What an export failure means to the user (card 0091).
  static func message(_ error: DeliverableExport.ExportError) -> LocalizedStringResource {
    switch error {
    case .readOnlyTarget(let reason): .app("\(reason)")
    case .sizeMismatch:
      .app("The image and its starless are not the same size: separate the stars again.")
    case .rowOrderMismatch:
      .app("The image and its starless store their rows differently: separate the stars again.")
    case .cropTooLarge(let fraction):
      .app("A crop of \(number(fraction)) on each edge leaves nothing of the image.")
    case .invalidCrop(let fraction):
      .app("The crop \(number(fraction)) is not a fraction of the image.")
    case .invalidTemplate(let template):
      .app("The file name “\(template)” must be one name containing {name}.")
    case .needsStarless:
      .app("The star blends need the starless image: separate the stars first.")
    }
  }

  /// StarNet's last line: its log holds every progress percentage.
  private static func lastLine(_ log: String) -> String {
    let line = log.split(whereSeparator: \.isNewline).last { !$0.allSatisfy(\.isWhitespace) }
    return String((line ?? "").suffix(200))
  }

  /// `value` in the user's notation.
  private static func number(_ value: Double) -> String {
    AstroFormat(locale: .autoupdatingCurrent).parameter(value)
  }
}
