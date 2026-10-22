internal import Foundation
package import ProjectKit
internal import RenderKit
package import SwiftUI

/// One export: when, how many files, where, « Reveal in Finder ».
package struct ExportRecordRow: View {
  let record: ProjectExport
  var model: ExportStageModel
  @Environment(\.locale) private var locale

  /// The row of `record`, revealed through `model`.
  package init(record: ProjectExport, model: ExportStageModel) {
    self.record = record
    self.model = model
  }

  package var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
        Text(verbatim: date)
        Text(.app("\(record.files.count) files")).font(.caption).foregroundStyle(.secondary)
        Text(verbatim: record.folder).font(.caption).foregroundStyle(.secondary)
          .lineLimit(1).truncationMode(.middle)
      }
      Spacer()
      Button(.app("Reveal in Finder")) { model.reveal(record) }
        .accessible(
          .stageControl("export", "reveal.\(record.id)"), label: .app("Reveal in Finder"))
    }
  }

  private var date: String {
    Date(timeIntervalSince1970: Double(record.createdAt) / 1000)
      .formatted(.dateTime.locale(locale).year().month().day().hour().minute())
  }
}
