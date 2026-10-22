internal import ProcessKit
internal import RenderKit
internal import SwiftUI

/// The Studio's catalogue (card 0087): the registry by stage; a process that cannot be the next
/// step is greyed with its reason, never hidden (R2).
struct StudioCatalogueView: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  var body: some View {
    List {
      ForEach(model.catalogue) { group in
        Section {
          ForEach(group.entries) { entry in row(entry) }
        } header: {
          Text(Self.stageTitle(group.stage))
        }
      }
    }
    .listStyle(.sidebar)
  }

  private func row(_ entry: StudioWorkspaceModel.Entry) -> some View {
    let title = ProcessKitResources.title(entry.title, locale: locale)
    return Button {
      model.choose(entry.id)
    } label: {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
        Text(title)
        if let reason = entry.unavailableReason {
          Text(verbatim: reason).font(.caption).foregroundStyle(DesignColor.textSecondary.color)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .buttonStyle(.plain)
    .opacity(entry.unavailableReason == nil ? 1 : 0.5)
    .accessible(.studioProcess(entry.id), label: title)
  }

  /// A stage's heading.
  static func stageTitle(_ stage: ProcessStage) -> LocalizedStringResource {
    switch stage {
    case .linear: .app("Linear")
    case .nonlinear: .app("Stretched")
    case .any: .app("Linear or stretched")
    }
  }
}
