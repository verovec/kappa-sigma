package import Foundation
package import StackKit

/// How the Stacking stage runs a night: the StackKit run itself, the clock that names it and the
/// scratch folder Siril works in.
package nonisolated struct RunServices: Sendable {
  /// Starts a preprocessing run; its stream ends with `.finished`, or throws.
  package typealias Run =
    @Sendable (PreprocessRequest) -> AsyncThrowingStream<
      PreprocessEvent, any Error
    >

  package var run: Run
  package var now: @Sendable () -> Date
  /// Where each run's Siril work folder (`run_<id>`) goes; it is removed when the run ends.
  package var scratch: URL
  /// The zone the run id is written in: the user's.
  package var timeZone: TimeZone

  /// Services from their parts.
  package init(
    run: @escaping Run, now: @escaping @Sendable () -> Date = { Date() },
    scratch: URL = FileManager.default.temporaryDirectory
      .appendingPathComponent("AstroStack/Work", isDirectory: true),
    timeZone: TimeZone = .current
  ) {
    self.run = run
    self.now = now
    self.scratch = scratch
    self.timeZone = timeZone
  }

  /// `Preprocessor` over the installed Siril (pipe mode); a missing Siril ends the stream with
  /// `SirilError.notInstalled`, never another tool (R2).
  package static let live = Self(run: { request in
    do {
      let binary = try SirilTool.locate()
      let runner = SirilRunner.make(mode: .default, binary: binary, work: request.work)
      return Preprocessor(tools: Preprocessor.Tools(runner: runner)).run(request)
    } catch {
      return AsyncThrowingStream { $0.finish(throwing: error) }
    }
  })

  /// The id of a run started at `date`: the legacy `yyyyMMdd_HHmmss`, so a stack folder reads
  /// like a legacy run's.
  package static func runID(at date: Date, in zone: TimeZone) -> String {
    let hour = Date.FormatStyle.Symbol.VerbatimHour.twoDigits(
      clock: .twentyFourHour, hourCycle: .zeroBased)
    let day: Date.FormatString = "\(year: .padded(4))\(month: .twoDigits)\(day: .twoDigits)"
    let time: Date.FormatString = "\(hour: hour)\(minute: .twoDigits)\(second: .twoDigits)"
    let calendar = Calendar(identifier: .gregorian)
    return [day, time].map {
      date.formatted(Date.VerbatimFormatStyle(format: $0, timeZone: zone, calendar: calendar))
    }.joined(separator: "_")
  }

  /// The id of a run starting now.
  package var nextRunID: String { Self.runID(at: now(), in: timeZone) }
}
