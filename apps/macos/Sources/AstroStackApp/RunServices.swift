package import Foundation
package import StackKit

/// How the Stacking stage runs a night: the StackKit run itself, the clock that names it, the
/// scratch folder Siril works in and the room left there.
package nonisolated struct RunServices: Sendable {
  /// Starts a preprocessing run; its stream ends with `.finished`, or throws.
  package typealias Run =
    @Sendable (PreprocessRequest) -> AsyncThrowingStream<
      PreprocessEvent, any Error
    >

  package var run: Run
  package var now: @Sendable () -> Date
  /// Where each run's Siril work folder (`run_<id>`) goes, read when a run starts (Settings may
  /// have moved it); the folder is removed when the run ends.
  package var scratchFolder: @Sendable () -> URL
  /// The bytes left on the volume of a folder; `nil` when the volume does not say (card 0098).
  package var room: @Sendable (URL) -> Int64?
  /// The zone the run id is written in: the user's.
  package var timeZone: TimeZone

  /// Services from their parts.
  package init(
    run: @escaping Run, now: @escaping @Sendable () -> Date = { Date() },
    scratch: URL = ScratchSetting.defaultFolder,
    timeZone: TimeZone = .current,
    room: @escaping @Sendable (URL) -> Int64? = ScratchSpace.available(at:),
    scratchFolder: (@Sendable () -> URL)? = nil
  ) {
    self.run = run
    self.now = now
    // A fixed folder unless a reader is given (the live services read Settings at each run).
    self.scratchFolder = scratchFolder ?? { scratch }
    self.room = room
    self.timeZone = timeZone
  }

  /// `Preprocessor` over the installed Siril (pipe mode); a missing Siril ends the stream with
  /// `SirilError.notInstalled`, never another tool (R2).
  package static let live = Self(
    run: { request in
      do {
        let binary = try SirilTool.locate()
        let runner = SirilRunner.make(mode: .default, binary: binary, work: request.work)
        return Preprocessor(tools: Preprocessor.Tools(runner: runner)).run(request)
      } catch {
        return AsyncThrowingStream { $0.finish(throwing: error) }
      }
    }, scratchFolder: { ScratchSetting().folder })

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

  /// The scratch folder runs go to now.
  package var scratch: URL { scratchFolder() }

  /// The id of a run starting now.
  package var nextRunID: String { Self.runID(at: now(), in: timeZone) }
}
