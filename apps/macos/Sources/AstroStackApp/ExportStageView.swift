internal import RenderKit
package import SwiftUI

/// The Export stage of one stack (card 0091): star separation and the form on the left, the
/// files written and the exports recorded on the right; StarNet's progress in a sheet.
package struct ExportStageView: View {
  var model: ExportStageModel
  @Environment(\.locale) private var locale

  /// The stage of `model`.
  package init(model: ExportStageModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      if let failure = model.failure {
        Label {
          Text(failure.message)
        } icon: {
          Image(systemName: "exclamationmark.triangle")
        }
        .foregroundStyle(DesignColor.statusAttention.color)
        .padding(.horizontal, DesignMetrics.spacingM)
        .padding(.bottom, DesignMetrics.spacingS)
      }
      HStack(alignment: .top, spacing: 0) {
        ScrollView {
          VStack(alignment: .leading, spacing: DesignMetrics.spacingL) {
            StarSeparationSection(model: model)
            ExportForm(model: model)
          }
          .padding(DesignMetrics.spacingM)
        }
        .frame(width: 360)
        Divider()
        ExportRecordList(model: model)
      }
    }
    // Shown while StarNet runs; it closes by itself when the separation ends or is cancelled.
    .sheet(isPresented: Binding(get: { model.isSeparating }, set: { _ in })) {
      StarSeparationSheet(model: model)
    }
  }

  /// The stage's title and its one action, Export.
  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingM) {
      SectionHeader(
        .app("Export"),
        detail: .app(
          "Written outside the stack; each export records what, where and from which step."),
        help: StageHelp.help(.export, locale: locale))
      Spacer()
      Button(.app("Export")) { Task { await model.export() } }
        .disabled(!model.canExport)
        .accessible(.stageControl("export", "export"), label: .app("Export"))
    }
    .padding(DesignMetrics.spacingM)
  }
}
