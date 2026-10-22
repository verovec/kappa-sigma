internal import Foundation
internal import Synchronization

/// Numbers a run's steps and turns its lines into ordered `PreprocessEvent`s.
final class RunEmitter: Sendable {
  let steps: Int
  private let sink: @Sendable (PreprocessEvent) -> Void
  private let current = Mutex<(step: Int, title: String)>((0, ""))

  init(steps: Int, sink: @escaping @Sendable (PreprocessEvent) -> Void) {
    self.steps = steps
    self.sink = sink
  }

  /// Starts the next step.
  func begin(_ title: String) {
    let step = current.withLock { state in
      state = (state.step + 1, title)
      return state.step
    }
    sink(.progress(.init(step: step, steps: steps, title: title, percent: nil, line: "")))
  }

  /// A journal line of the current step, with Siril's percentage when it carries one.
  func line(_ text: String) {
    let (step, title) = current.withLock { $0 }
    let percent = SirilLine(parsing: text).percent
    sink(.progress(.init(step: step, steps: steps, title: title, percent: percent, line: text)))
  }

  /// A stage's quick look.
  func preview(stage: String, png: URL) {
    sink(.preview(.init(stage: stage, pngPath: png.path)))
  }

  /// A lane paused at the frame review (card 0069).
  func frames(_ frames: PreprocessEvent.Frames) {
    sink(.frames(frames))
  }
}
