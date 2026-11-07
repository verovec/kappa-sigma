package import Foundation
internal import RenderKit
package import SwiftUI

/// Where the next export goes (card 0152): on this Mac and/or on S3 (a connection, a bucket, a
/// prefix), each with the destination it resolves to — shown = written (R2) — and the upload's
/// progress with « Cancel » while it runs.
package struct ExportTargetsForm: View {
  @Bindable var model: ExportStageModel

  /// The targets of the next export of `model`.
  package init(model: ExportStageModel) { self.model = model }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXS) {
      Text(.app("Destinations")).font(.headline)
      Toggle(isOn: $model.local) { Text(.app("On this Mac")) }
        .accessible(.stageControl("export", "target.local"), label: .app("On this Mac"))
      Toggle(isOn: Self.s3On(model)) { Text(.app("On S3")) }
        .disabled(model.s3 == nil && model.s3Connections.isEmpty)
        .accessible(.stageControl("export", "target.s3"), label: .app("On S3"))
      if model.s3 != nil {
        s3Fields
      } else if model.s3Connections.isEmpty {
        Text(.app("Add an S3 connection in Settings › S3 connections first."))
          .font(.caption).foregroundStyle(.secondary)
      }
      if !model.local && model.s3 == nil {
        Text(UserFacingError.exportS3(.noDestination).message)
          .font(.caption).foregroundStyle(DesignColor.statusError.color)
      }
      uploadLines
    }
  }

  /// What the S3 copy says while and after it runs: what the key could not check (card 0185),
  /// the file being sent with « Cancel ».
  @ViewBuilder private var uploadLines: some View {
    if model.remoteUnchecked {
      Text(
        .app("This key cannot see existing objects: the service was told never to replace one.")
      )
      .font(.caption).foregroundStyle(.secondary)
    }
    if let progress = model.uploadProgress {
      HStack {
        Text(.app("Uploading file \(progress.file) of \(progress.files)…")).font(.caption)
        Spacer()
        Button(.app("Cancel")) { model.cancelExport() }
      }
    }
  }

  @ViewBuilder private var s3Fields: some View {
    let connections = model.s3Connections
    if connections.isEmpty {
      Text(.app("Add an S3 connection in Settings › S3 connections first."))
        .font(.caption).foregroundStyle(.secondary)
    } else {
      Picker(selection: Self.connection(model)) {
        ForEach(connections) { Text(verbatim: $0.name).tag(Optional($0.id)) }
      } label: {
        Text(.app("Connection"))
      }
    }
    TextField(.app("Bucket"), text: Self.field(model, \.bucket))
    TextField(.app("Prefix"), text: Self.field(model, \.prefix))
    if let remote = model.remoteFolder {
      Text(verbatim: remote).font(.caption).textSelection(.enabled)
        .lineLimit(2).truncationMode(.middle)
    }
  }

  /// On: a target over the first connection, bucket and prefix to fill; off: no S3 copy.
  package static func s3On(_ model: ExportStageModel) -> Binding<Bool> {
    Binding(
      get: { model.s3 != nil },
      set: { on in
        guard on else {
          model.s3 = nil
          return
        }
        // Never a target over a connection that does not exist: without one it stays off.
        guard model.s3 == nil, let first = model.s3Connections.first else { return }
        model.s3 = S3Target(connectionID: first.id, bucket: "", prefix: "")
      })
  }

  /// The connection picked for the S3 copy.
  package static func connection(_ model: ExportStageModel) -> Binding<UUID?> {
    Binding(
      get: { model.s3?.connectionID },
      set: { if let id = $0 { model.s3?.connectionID = id } })
  }

  /// A text field of the S3 target (bucket, prefix).
  package static func field(_ model: ExportStageModel, _ path: WritableKeyPath<S3Target, String>)
    -> Binding<String>
  {
    Binding(get: { model.s3?[keyPath: path] ?? "" }, set: { model.s3?[keyPath: path] = $0 })
  }
}
