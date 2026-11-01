internal import Foundation
package import ProjectKit
package import RenderKit
package import SwiftUI

/// One export: when, how many files, where — on this Mac and/or on S3, each with its badge —
/// « Reveal in Finder », « Copy S3 URL », and « Resend to S3 » after a failed upload (card 0152).
package struct ExportRecordRow: View {
  let record: ProjectExport
  var model: ExportStageModel
  @Environment(\.locale) private var locale

  /// The row of `record`, acted on through `model`.
  package init(record: ProjectExport, model: ExportStageModel) {
    self.record = record
    self.model = model
  }

  package var body: some View {
    HStack(alignment: .firstTextBaseline) {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
        Text(verbatim: date)
        Text(.app("\(record.files.count) files")).font(.caption).foregroundStyle(.secondary)
        if let folder = record.folder {
          place(folder, badge: StatusBadge(.ok, .app("On this Mac")))
        }
        if let url = record.remoteURL {
          place(url, badge: Self.remoteBadge(record.remoteStatus))
          if record.remoteStatus == .failed, let error = record.remoteError {
            Text(verbatim: error).font(.caption).foregroundStyle(DesignColor.statusError.color)
              .textSelection(.enabled)
          }
        }
      }
      Spacer()
      actions
    }
  }

  private func place(_ text: String, badge: StatusBadge) -> some View {
    HStack(spacing: DesignMetrics.spacingXS) {
      badge
      Text(verbatim: text).font(.caption).foregroundStyle(.secondary)
        .lineLimit(1).truncationMode(.middle).textSelection(.enabled)
    }
  }

  @ViewBuilder private var actions: some View {
    VStack(alignment: .trailing, spacing: DesignMetrics.spacingXXS) {
      if record.folder != nil {
        Button(.app("Reveal in Finder")) { model.reveal(record) }
          .accessible(
            .stageControl("export", "reveal.\(record.id)"), label: .app("Reveal in Finder"))
      }
      if record.remoteURL != nil {
        Button(.app("Copy S3 URL")) { model.copyRemoteURL(record) }
          .accessible(.stageControl("export", "copy.\(record.id)"), label: .app("Copy S3 URL"))
      }
      if Self.canResend(record) {
        Button(.app("Resend to S3")) { model.startResend(record) }
          .disabled(model.isExporting)
          .accessible(.stageControl("export", "resend.\(record.id)"), label: .app("Resend to S3"))
      }
    }
  }

  /// The S3 copy's badge: uploaded, or failed.
  package static func remoteBadge(_ status: ProjectExport.RemoteStatus) -> StatusBadge {
    status == .failed
      ? StatusBadge(.error, .app("S3 upload failed")) : StatusBadge(.ok, .app("On S3"))
  }

  /// « Resend to S3 » is offered for a failed upload whose files are still kept on this Mac.
  package static func canResend(_ record: ProjectExport) -> Bool {
    record.remoteStatus == .failed && record.folder != nil
  }

  private var date: String {
    Date(timeIntervalSince1970: Double(record.createdAt) / 1000)
      .formatted(.dateTime.locale(locale).year().month().day().hour().minute())
  }
}
