package import Foundation
package import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Studio's catalogue (card 0087): the registry by stage; a process that cannot be the next
/// step is greyed with its reason, never hidden (R2).
package struct StudioCatalogueView: View {
  let model: StudioWorkspaceModel
  @Environment(\.locale) private var locale

  package var body: some View {
    List {
      ForEach(model.catalogue) { group in
        Section {
          ForEach(group.entries) { entry in StudioCatalogueRow(entry: entry, model: model) }
        } header: {
          Text(Self.stageTitle(group.stage))
        }
      }
    }
    .listStyle(.sidebar)
  }

  /// Why a process is greyed, worded for `locale`.
  package static func reason(_ unavailable: StudioUnavailable, locale: Locale) -> String {
    switch unavailable {
    case .missing(let roles):
      let names = roles.map { String(localized: roleName($0, locale: locale)) }
        .joined(separator: ", ")
      return String(localized: .app("Needs \(names)", locale: locale))
    case .linearAfterStretch:
      return String(localized: .app("Runs on linear data: undo the stretch first", locale: locale))
    case .unsolved:
      return String(localized: .app("Solve the image first (plate solving)", locale: locale))
    case .onCombinedImage:
      return String(localized: .app("Acts on the combined image: apply it there", locale: locale))
    case .toolOnCombinedImage:
      return String(
        localized: .app("Runs a host tool: on the combined image only", locale: locale))
    case .needsColourLayer:
      return String(
        localized: .app("Needs a colour layer: this branch is an emission line", locale: locale))
    case .toolMissing:
      return String(
        localized: .app(
          "Needs Siril, not found: install it, then reopen the project", locale: locale))
    }
  }

  private static func roleName(_ role: LayerRole, locale: Locale) -> LocalizedStringResource {
    switch role {
    case .color: .app("a colour layer", locale: locale)
    case .luminance: .app("a luminance layer", locale: locale)
    case .emission: .app("an emission layer", locale: locale)
    case .starless: .app("a starless layer", locale: locale)
    case .stars: .app("a stars layer", locale: locale)
    case .mask: .app("a mask layer", locale: locale)
    case .backgroundModel: .app("a background model", locale: locale)
    }
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
