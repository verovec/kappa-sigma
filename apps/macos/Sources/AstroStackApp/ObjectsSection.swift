internal import Foundation
internal import RenderKit
internal import StackKit
internal import SwiftUI

/// The sidebar's Objects (card 0130), under the journey stages: what the search finds, else the
/// object the project is of; without Siril, its install card — no other list stands in (R2).
struct ObjectsSection: View {
  @Bindable var objects: ObjectSearchModel
  /// The stack's `OBJECT`, matched once the catalogue is read.
  let projectObject: String?
  @State private var card: InstallCardModel?
  @Environment(\.locale) private var locale

  var body: some View {
    Section {
      content
    } header: {
      SectionHeader(.app("Objects"), help: ObjectsHelp.help(locale: locale))
    }
    .task(id: projectObject) { await objects.load(projectObject: projectObject) }
    .task(id: objects.unavailable) { makeCard() }
    // Siril found by « Re-check »: the catalogue is read again.
    .onChange(of: card?.state) { _, state in
      guard case .found = state else { return }
      objects.retry()
      Task { await objects.load(projectObject: projectObject) }
    }
  }

  @ViewBuilder private var content: some View {
    if case .sirilMissing = objects.unavailable, let card {
      InstallCard(
        tool: HostTool.siril.productName, reason: .app("Its object lists are Siril’s."),
        installURL: HostTool.siril.installURL, model: card)
    } else if let unavailable = objects.unavailable {
      StatusBadge(.attention, ObjectsHelp.reason(unavailable))
    } else if objects.query.isEmpty {
      if let selected = objects.selected {
        row(selected)
      } else {
        Text(.app("Search a name: M 31, NGC 7000, Sh2-132…"))
          .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
      }
    } else if objects.results.isEmpty {
      Text(.app("No object by that name."))
        .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
    } else {
      ForEach(objects.results, id: \.name) { row($0) }
    }
  }

  private func row(_ object: SkyObject) -> some View {
    Button {
      objects.choose(object)
    } label: {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
        Text(verbatim: object.name)
        if let common = object.commonNames.first {
          Text(verbatim: common).font(.caption)
            .foregroundStyle(DesignColor.textSecondary.color)
        }
      }
    }
    .buttonStyle(.plain)
    .accessible(.objectResult(object.name), verbatim: object.name)
  }

  /// The install card of a missing Siril, made once; its re-check looks for `siril-cli` again.
  private func makeCard() {
    guard case .sirilMissing = objects.unavailable else {
      card = nil
      return
    }
    guard card == nil else { return }
    card = InstallCardModel(state: .missing) { @concurrent in
      let path = SirilTool.path()
      return FileManager.default.isExecutableFile(atPath: path) ? URL(fileURLWithPath: path) : nil
    }
  }
}
