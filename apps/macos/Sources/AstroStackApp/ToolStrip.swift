package import Foundation
package import RenderKit
package import StackKit
package import SwiftUI

/// The host tools as the welcome window and Settings › Tools show them.
///
/// A usable tool gets a badge, a missing or too old one an install card; nothing else is offered
/// in its place (R2).
package struct ToolStrip: View {
  private let model: WelcomeModel

  /// The strip over the model's last check and its install cards.
  package init(model: WelcomeModel) {
    self.model = model
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      HStack {
        SectionHeader(.app("Host tools"))
        Spacer()
        Button(.app("Re-check tools")) { Task { await model.recheckTools() } }
      }
      if model.tools.isEmpty {
        HStack(spacing: DesignMetrics.spacingS) {
          ProgressView().controlSize(.small)
          Text(.app("Checking tools…")).foregroundStyle(DesignColor.textSecondary.color)
        }
      }
      ForEach(model.tools) { row in
        if let found = Self.usable(row, card: model.cards[row.tool]?.state) {
          HStack(spacing: DesignMetrics.spacingS) {
            Text(verbatim: row.tool.productName).font(.headline)
            StatusBadge(.ok, Self.found(found)).lineLimit(1).truncationMode(.middle)
          }
        } else if let card = model.cards[row.tool] {
          InstallCard(
            tool: row.tool.productName, reason: Self.reason(row), installURL: row.tool.installURL,
            model: card)
        }
      }
    }
  }

  /// The tool as usable, by its card's latest verdict (its own « Re-check » or the strip's),
  /// else by the last check while the card re-checks or has none.
  nonisolated package static func usable(_ row: WelcomeModel.ToolRow, card: InstallCardModel.State?)
    -> ToolStatus?
  {
    switch card {
    case .found(let url)?:
      return row.status.isUsable ? row.status : .found(path: url.path, version: nil)
    case .missing?, .outdated?: return nil
    case .checking?, nil: return row.status.isUsable ? row.status : nil
    }
  }

  /// The badge words of a usable tool: its version when it reports one, and its path.
  nonisolated package static func found(_ status: ToolStatus) -> LocalizedStringResource {
    if case .found(let path, let version?) = status {
      return .app("Installed: \(version) — \(path)")
    }
    return .app("Installed: \(status.path)")
  }

  /// Why the tool is needed, or why the installed one cannot be used.
  nonisolated package static func reason(_ row: WelcomeModel.ToolRow) -> LocalizedStringResource {
    if case .tooOld(_, let version) = row.status {
      // The sentence the app already shows for a too old Siril, the only tool with a floor.
      return UserFacingError.siril(.tooOld(version: version)).message
    }
    return switch row.tool {
    case .siril: .app("Calibrates, registers and stacks the captures.")
    case .graxpert: .app("Extracts the background and denoises.")
    case .starnet: .app("Separates the stars from the nebula.")
    }
  }
}

extension HostTool {
  /// Where the user installs the tool; the app never downloads it (licences, StarNet).
  package var installURL: URL {
    switch self {
    case .siril: URL(string: "https://siril.org/download/") ?? URL(fileURLWithPath: "/")
    case .graxpert: URL(string: "https://graxpert.com") ?? URL(fileURLWithPath: "/")
    case .starnet: URL(string: "https://www.starnetastro.com") ?? URL(fileURLWithPath: "/")
    }
  }
}
