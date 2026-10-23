internal import Foundation
internal import ProjectKit
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The runs paused after a lane (card 0097), each with Continue and Discard.
///
/// What each stacked and what is left; Continue runs the same run, its lanes done reused, and
/// Discard deletes its row and kept masters, asked first. Never continued on its own.
struct PausedRunsView: View {
  var model: ProjectWindowModel
  @State private var discarding: ProjectStack?

  var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      ForEach(model.pausedRuns) { paused in
        HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
          Label {
            Text(Self.words(paused))
          } icon: {
            Image(systemName: "pause.circle")
          }
          Spacer()
          Button(.app("Continue")) { model.continueRun(paused.id) }
            .disabled(model.needsSave)
            .accessible(.stackingContinue(paused.id), label: .app("Continue"))
          Button(.app("Discard…"), role: .destructive) { discarding = paused }
            .accessible(.stackingDiscard(paused.id), label: .app("Discard…"))
        }
      }
    }
    .padding([.horizontal, .bottom], DesignMetrics.spacingM)
    .confirmationDialog(
      Text(.app("Discard this paused run?")), isPresented: isAsking, presenting: discarding
    ) { paused in
      Button(.app("Discard"), role: .destructive) {
        Task { await model.discardPausedRun(paused.id) }
      }
    } message: { _ in
      Text(.app("The masters it kept are deleted from the project."))
    }
  }

  private var isAsking: Binding<Bool> {
    Binding(get: { discarding != nil }, set: { if !$0 { discarding = nil } })
  }

  /// « Paused run 20261021_210000 — stacked: RGB · left: RGB-dualband ».
  static func words(_ paused: ProjectStack) -> LocalizedStringResource {
    let runID = URL(fileURLWithPath: paused.bundlePath).lastPathComponent
    let checkpoint = paused.checkpointJSON.flatMap {
      try? JSONDecoder().decode(PreprocessCheckpoint.self, from: Data($0.utf8))
    }
    let done = checkpoint?.lanesDone.joined(separator: ", ") ?? ""
    let left = checkpoint?.lanesLeft.joined(separator: ", ") ?? ""
    return .app("Paused run \(runID) — stacked: \(done) · left: \(left)")
  }
}
