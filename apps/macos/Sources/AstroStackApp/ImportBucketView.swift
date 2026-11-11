internal import RenderKit
package import SwiftUI

/// The bucket form of the Import sheet (card 0169): a connection of Settings, a bucket, and the
/// prefix browsed one level at a time — the frames are read where they are, never downloaded.
package struct ImportBucketView: View {
  var model: ImportBucketModel
  /// Called with the prefix to scan when the user asks for it.
  var onScan: (RemoteImportTarget) -> Void
  /// Opens Settings on its S3 tab (card 0177).
  var openSettings: OpenSettingsButton.Open

  /// A form over `model`; `onScan` receives the prefix chosen; `openSettings` opens the
  /// connections' editor.
  package init(
    model: ImportBucketModel, onScan: @escaping (RemoteImportTarget) -> Void,
    openSettings: @escaping OpenSettingsButton.Open = OpenSettingsButton.window
  ) {
    self.model = model
    self.onScan = onScan
    self.openSettings = openSettings
  }

  /// « S3 connections… »: the one place the connections are edited, a click away.
  package var settingsButton: OpenSettingsButton {
    OpenSettingsButton(tab: .s3, open: openSettings)
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingM) {
      connectionRow
      prefixRow
      folders
      if let error = model.error {
        StatusBadge(.error, error.message)
      }
      scanRow
    }
    .padding(DesignMetrics.spacingM)
    .frame(width: Self.width)
    // The folders are there when the form opens and when the connection changes: « Browse »
    // is for reading a level again, not a step to guess.
    .onAppear { model.browseIfUnread() }
    .onChange(of: model.connectionID) { model.browseIfUnread() }
  }

  private var connectionRow: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      HStack {
        Picker(selection: Binding(get: { model.connectionID }, set: { model.connectionID = $0 })) {
          Text(.app("Choose a connection")).tag(nil as UUID?)
          ForEach(model.connections) { connection in
            Text(verbatim: connection.name).tag(connection.id as UUID?)
          }
        } label: {
          Text(.app("Connection"))
        }
        .accessible(.importBucketConnection, label: .app("Connection"))
        settingsButton
      }
      TextField(
        text: Binding(get: { model.bucket }, set: { model.bucket = $0 }),
        prompt: Text(.app("bucket name, or s3://bucket/folder/"))
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

  /// Where the browse stands — every level a click away — and « Browse » to read it again.
  private var prefixRow: some View {
    HStack(spacing: DesignMetrics.spacingS) {
      Button {
        model.up()
      } label: {
        Image(systemName: "chevron.up")
      }
      .accessible(.importBucketUp, label: .app("One Level Up"))
      .disabled(model.parent == nil || model.isBrowsing)
      crumbs
      if model.isBrowsing {
        ProgressView().controlSize(.small)
      } else {
        Button(.app("Browse")) { model.browse() }
          .accessible(.importBrowse, label: .app("Browse"))
          .disabled(model.target == nil)
      }
    }
  }

  /// The path as crumbs, the deepest kept in view when it is longer than the row.
  private var crumbs: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: DesignMetrics.spacingXS) {
        ForEach(model.crumbs) { crumb in
          if !crumb.prefix.isEmpty {
            Image(systemName: "chevron.right")
              .font(.caption2).foregroundStyle(.tertiary).accessibilityHidden(true)
          }
          let here = crumb.prefix == model.prefix
          Button {
            model.enter(crumb.prefix)
          } label: {
            Text(verbatim: Self.crumbName(crumb))
              .font(.callout).fontWeight(here ? .semibold : .regular)
              .foregroundStyle(here ? .primary : .secondary)
          }
          .buttonStyle(.plain)
          .disabled(model.target == nil || model.isBrowsing)
          .accessible(.importBucketCrumb(crumb.prefix), verbatim: Self.crumbName(crumb))
        }
      }
    }
    .defaultScrollAnchor(.trailing)
    .frame(maxWidth: .infinity, alignment: .leading)
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
        VStack(alignment: .leading, spacing: Self.rowSpacing) {
          ForEach(model.folders, id: \.self) { folder in
            FolderRow(name: Self.name(of: folder)) { model.enter(folder) }
              .accessible(.importBucketFolder(folder), verbatim: Self.name(of: folder))
          }
        }
        .padding(DesignMetrics.spacingXS)
      }
      // A height of its own, not a maximum alone: a popover sizes its content to the ideal
      // height, and a scroll view's can be nothing — the folders listed would not show.
      .frame(height: Self.listHeight(rows: model.folders.count))
      .background(
        .quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: DesignMetrics.radiusMedium)
      )
      .disabled(model.isBrowsing)
    }
  }

  /// What a scan would read, said before it is asked for: the root is the whole bucket.
  private var scanRow: some View {
    HStack(alignment: .firstTextBaseline) {
      if let target = model.target {
        if target.prefix.isEmpty {
          StatusBadge(.attention, .app("The bucket's root: a scan reads every folder of it."))
        } else {
          Text(verbatim: target.path)
            .font(.caption).foregroundStyle(.secondary)
            .lineLimit(1).truncationMode(.head).textSelection(.enabled)
        }
      }
      Spacer()
      Button(.app("Scan This Prefix")) {
        if let target = model.target { onScan(target) }
      }
      .accessible(.importBucketScan, label: .app("Scan This Prefix"))
      .disabled(model.target == nil || model.isBrowsing)
      .keyboardShortcut(.defaultAction)
    }
  }

  /// The form's width.
  static let width: CGFloat = 480
  /// The height of one folder row.
  static let rowHeight: CGFloat = 24
  /// The gap between two folder rows.
  static let rowSpacing: CGFloat = 2
  /// The tallest the list grows before it scrolls.
  static let maxListHeight: CGFloat = 260

  /// The height of a list of `rows` folders: all of them, up to `maxListHeight`.
  package static func listHeight(rows: Int) -> CGFloat {
    let content =
      CGFloat(rows) * rowHeight + CGFloat(max(rows - 1, 0)) * rowSpacing
      + 2 * DesignMetrics.spacingXS
    return min(content, maxListHeight)
  }

  /// What a crumb reads: its folder, or the bucket for the root (`/` before one is named).
  static func crumbName(_ crumb: ImportBucketModel.Crumb) -> String {
    crumb.name.isEmpty ? "/" : crumb.name
  }

  /// The last part of a full prefix: what the user reads as the folder's name.
  package static func name(of prefix: String) -> String {
    prefix.split(separator: "/").last.map(String.init) ?? prefix
  }
}

/// One folder of the level: the whole row is the click, and says so under the pointer.
private struct FolderRow: View {
  let name: String
  let enter: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: enter) {
      HStack(spacing: DesignMetrics.spacingS) {
        Image(systemName: "folder").foregroundStyle(.secondary)
        Text(verbatim: name).lineLimit(1).truncationMode(.middle)
        Spacer(minLength: DesignMetrics.spacingS)
        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
      }
      .padding(.horizontal, DesignMetrics.spacingS)
      .frame(maxWidth: .infinity, minHeight: ImportBucketView.rowHeight, alignment: .leading)
      .background(
        isHovered ? AnyShapeStyle(.selection.opacity(0.35)) : AnyShapeStyle(.clear),
        in: RoundedRectangle(cornerRadius: DesignMetrics.radiusSmall)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
