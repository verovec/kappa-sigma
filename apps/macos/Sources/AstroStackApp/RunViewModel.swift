package import Foundation
import Observation
package import StackKit

/// The Run panel's state, reduced from one preprocessing run's event stream.
///
/// Steps, percentage, stage previews and journal while it runs; what it left behind once it
/// stops. The model only shows what the run reports (R2): it never retries, skips or reorders a step.
@Observable
package final class RunViewModel {
  /// Where a step stands.
  package enum StepState: Equatable, Sendable {
    case pending, running, done, failed, cancelled
  }

  /// One step of the run, as StackKit titles it.
  package struct Step: Identifiable, Equatable, Sendable {
    /// 1-based position in the run.
    package let number: Int
    /// StackKit's title; empty until the step begins.
    package var title: String
    package var state: StepState
    package var id: Int { number }
  }

  /// One journal line: a Siril line or a StackKit warning (`⚠ …`).
  package struct Line: Identifiable, Equatable, Sendable {
    package let id: Int
    /// The step it belongs to.
    package let step: Int
    package let text: String
    package var isWarning: Bool { text.hasPrefix("⚠") }
  }

  /// A stage's quick look (`master_RGB`, `combined`).
  package struct Thumbnail: Identifiable, Equatable, Sendable {
    package let stage: String
    package let url: URL
    package var id: String { stage }
  }

  /// Where the run stands.
  package enum Phase: Equatable, Sendable {
    case running, finished, cancelled
    case failed(UserFacingError)
  }

  /// Journal lines kept for a failed run's summary.
  package static let tailLength = 20

  package let runID: String
  /// The run's folder in the project (`stacks/<run_id>`).
  package let output: URL
  package private(set) var phase = Phase.running
  package private(set) var steps: [Step] = []
  /// Siril's percentage on the current step, when its last line carried one.
  package private(set) var percent: Int?
  package private(set) var previews: [Thumbnail] = []
  package private(set) var journal: [Line] = []
  /// The finished run.
  package private(set) var result: PreprocessResult?
  /// The files a cancelled or failed run left in `output` (masters stay, no bundle).
  package private(set) var kept: [String] = []
  /// Text the journal is filtered on; empty shows every line.
  package var journalFilter = ""
  @ObservationIgnored private var task: Task<Void, Never>?

  /// A run `runID` writing into `output`.
  package init(runID: String, output: URL) {
    self.runID = runID
    self.output = output
  }

  package var isRunning: Bool { phase == .running }

  /// The journal lines containing `journalFilter`, ignoring case.
  package var shownJournal: [Line] {
    journalFilter.isEmpty
      ? journal : journal.filter { $0.text.localizedStandardContains(journalFilter) }
  }

  /// The last lines of the journal, shown when a run fails.
  package var journalTail: [Line] { Array(journal.suffix(Self.tailLength)) }

  // MARK: - Reduction

  /// Applies one event of the run's stream.
  package func reduce(_ event: PreprocessEvent) {
    switch event {
    case .progress(let progress): reduce(progress)
    case .preview(let preview):
      let thumbnail = Thumbnail(stage: preview.stage, url: URL(fileURLWithPath: preview.pngPath))
      if let index = previews.firstIndex(where: { $0.stage == preview.stage }) {
        previews[index] = thumbnail
      } else {
        previews.append(thumbnail)
      }
    case .finished(let result):
      self.result = result
      for index in steps.indices { steps[index].state = .done }
      percent = nil
      phase = .finished
    }
  }

  private func reduce(_ progress: PreprocessEvent.Progress) {
    if steps.count < progress.steps {
      steps += (steps.count + 1...progress.steps).map {
        Step(number: $0, title: "", state: .pending)
      }
    }
    for index in steps.indices where steps[index].number < progress.step {
      steps[index].state = .done
    }
    guard steps.indices.contains(progress.step - 1) else { return }
    steps[progress.step - 1].title = progress.title
    steps[progress.step - 1].state = .running
    if progress.line.isEmpty {
      percent = nil
    } else {
      journal.append(Line(id: journal.count, step: progress.step, text: progress.line))
      if let value = progress.percent { percent = value }
    }
  }

  // MARK: - Running

  /// Runs the stream `events` returns, reducing each event; `completion` gets the result, or the
  /// error (`CancellationError` after Cancel), and `settled()` waits for it too.
  ///
  /// A result always wins: a Cancel landing after `.finished` keeps the finished run. A stream
  /// that ends without its result, uncancelled, is a failure (`runIncomplete`), never shown as
  /// cancelled.
  package func start(
    _ events:
      @escaping @Sendable () async throws -> AsyncThrowingStream<PreprocessEvent, any Error>,
    completion: @escaping (Result<PreprocessResult, any Error>) async -> Void = { _ in }
  ) {
    task = Task {
      let outcome: Result<PreprocessResult, any Error>
      do {
        for try await event in try await events() { reduce(event) }
        guard let result else {
          try Task.checkCancellation()
          throw UserFacingError.runIncomplete
        }
        outcome = .success(result)
      } catch {
        if let result {
          outcome = .success(result)
        } else {
          outcome = .failure(error)
          stop(Task.isCancelled || error is CancellationError ? nil : error)
        }
      }
      await completion(outcome)
    }
  }

  /// Cancels the run: StackKit stops Siril, the finished masters stay, no bundle is written.
  package func cancel() {
    task?.cancel()
  }

  /// Returns once the run has ended and its completion has run.
  package func settled() async {
    await task?.value
  }

  /// Marks the running step and lists what the run left behind; `error` nil means cancelled.
  private func stop(_ error: (any Error)?) {
    for index in steps.indices where steps[index].state == .running {
      steps[index].state = error == nil ? .cancelled : .failed
    }
    percent = nil
    phase = error.map { .failed(UserFacingError($0)) } ?? .cancelled
    let names = (try? FileManager.default.contentsOfDirectory(atPath: output.path)) ?? []
    kept = names.filter { !$0.hasPrefix(".") }.sorted()
  }
}
