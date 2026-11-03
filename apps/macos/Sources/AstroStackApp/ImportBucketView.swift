internal import RenderKit
package import SwiftUI

/// The bucket form of the Import sheet (card 0169): a connection of Settings, a bucket, and the
/// prefix browsed one level at a time — the frames are read where they are, never downloaded.
package struct ImportBucketView: View {
  var model: ImportBucketModel
  /// Called with the prefix to scan when the user asks for it.
  var onScan: (RemoteImportTarget) -> Void

  /// A form over `model`; `onScan` receives the prefix chosen.
  package init(model: ImportBucketModel, onScan: @escaping (RemoteImportTarget) -> Void) {
    self.model = model
    self.onScan = onScan
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      connectionRow
      prefixRow
      folders
      if let error = model.error {
        StatusBadge(.error, error.message)
      }
      HStack {
        Spacer()
        Button(.app("Scan This Prefix")) {
          if let target = model.target { onScan(target) }
        }
        .accessible(.importBucketScan, label: .app("Scan This Prefix"))
        .disabled(model.target == nil || model.isBrowsing)
        .keyboardShortcut(.defaultAction)
      }
    }
    .padding(DesignMetrics.spacingM)
    .frame(width: 420)
  }

  private var connectionRow: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      Picker(selection: Binding(get: { model.connectionID }, set: { model.connectionID = $0 })) {
        Text(.app("Choose a connection")).tag(nil as UUID?)
        ForEach(model.connections) { connection in
          Text(verbatim: connection.name).tag(connection.id as UUID?)
        }
      } label: {
        Text(.app("Connection"))
      }
      .accessible(.importBucketConnection, label: .app("Connection"))
      TextField(
        text: Binding(get: { model.bucket }, set: { model.bucket = $0 }),
        prompt: Text(.app("bucket name"))
      ) {
        Text(.app("Bucket"))
      }
      .accessible(.importBucketName, label: .app("Bucket"))
      .onSubmit { model.browse() }
      if model.connections.isEmpty {
        StatusBadge(
          .attention, .app("No S3 connection yet: add one in Settings › S3 connections."))
      }
    }
  }

  private var prefixRow: some View {
    HStack {
      Button {
        model.up()
      } label: {
        Image(systemName: "chevron.up")
      }
      .accessible(.importBucketUp, label: .app("One Level Up"))
      .disabled(model.parent == nil || model.isBrowsing)
      Text(verbatim: model.prefix.isEmpty ? "/" : model.prefix)
        .font(.caption).lineLimit(1).truncationMode(.head)
      Spacer()
      if model.isBrowsing {
        ProgressView().controlSize(.small)
      } else {
        Button(.app("Browse")) { model.browse() }
          .accessible(.importBrowse, label: .app("Browse"))
          .disabled(model.target == nil)
      }
    }
  }

  /// The folders of the level, as the bucket answered them; an empty level says so rather than
  /// leaving the list blank (a failed listing keeps the last one and shows its badge).
  @ViewBuilder private var folders: some View {
    if model.folders.isEmpty {
      // Only once a listing answered: before that, and after one that failed, nobody has read
      // this level, and saying it is empty would be a verdict of ours.
      if model.hasListed && model.error == nil {
        Text(.app("No folder at this level."))
          .font(.caption).foregroundStyle(.secondary)
      }
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 2) {
          ForEach(model.folders, id: \.self) { folder in
            Button {
              model.enter(folder)
            } label: {
              Label(Self.name(of: folder), systemImage: "folder")
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessible(.importBucketFolder(folder), verbatim: Self.name(of: folder))
          }
        }
      }
      .frame(maxHeight: 180)
    }
  }

  /// The last part of a full prefix: what the user reads as the folder's name.
  package static func name(of prefix: String) -> String {
    prefix.split(separator: "/").last.map(String.init) ?? prefix
  }
}
