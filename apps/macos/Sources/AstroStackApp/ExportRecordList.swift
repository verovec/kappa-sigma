internal import RenderKit
package import SwiftUI

/// The files the last export wrote and every export of the stack, newest first: when, how many
/// files, where, « Reveal in Finder ».
package struct ExportRecordList: View {
  var model: ExportStageModel

  /// The exports that `model` lists.
  package init(model: ExportStageModel) {
    self.model = model
  }

  package var body: some View {
    if model.exports.isEmpty {
      EmptyState(
        .app("Exports"), message: .app("Each export is listed here with its files and folder."),
        systemImage: "tray")
    } else {
      List {
        if !model.written.isEmpty {
          Section(.app("Written")) {
            ForEach(model.written, id: \.self) { url in
              Text(verbatim: url.lastPathComponent).font(DesignMetrics.valueFont)
            }
          }
        }
        Section(.app("Exports")) {
          ForEach(model.exports) { record in ExportRecordRow(record: record, model: model) }
        }
      }
    }
  }
}
