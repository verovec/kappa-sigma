package import Foundation
package import SwiftUI

/// A host tool the app invokes but does not bundle (Siril, GraXpert, StarNet): its state, why it
/// is needed, where to install it, and « Re-check ».
package struct InstallCard: View {
  private let tool: String
  private let reason: LocalizedStringResource
  private let installURL: URL
  private let model: InstallCardModel

  /// The card of `tool` (its product name, never translated), `reason` it is needed.
  package init(
    tool: String, reason: LocalizedStringResource, installURL: URL, model: InstallCardModel
  ) {
    self.tool = tool
    self.reason = reason
    self.installURL = installURL
    self.model = model
  }

  /// The badge's kind for `state`.
  nonisolated package static func status(of state: InstallCardModel.State) -> DesignStatus {
    switch state {
    case .found: .ok
    case .outdated, .unusable: .attention
    case .missing, .checking: .unavailable
    }
  }

  /// The badge's words for `state`.
  nonisolated package static func label(
    of state: InstallCardModel.State, locale: Locale? = nil
  ) -> LocalizedStringResource {
    switch state {
    case .missing: .renderKit("Not installed", locale: locale)
    case .checking: .renderKit("Checking…", locale: locale)
    case .found(let url): .renderKit("Installed: \(url.path)", locale: locale)
    case .outdated(let version): .renderKit("Too old: \(version)", locale: locale)
    case .unusable(let url, _): .renderKit("Installed but cannot run: \(url.path)", locale: locale)
    }
  }

  /// What to do about an install that cannot run (selectable: it holds the command), else `nil`.
  nonisolated package static func detail(of state: InstallCardModel.State) -> String? {
    if case .unusable(_, let reason) = state { reason } else { nil }
  }

  package var body: some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
      HStack(alignment: .firstTextBaseline, spacing: DesignMetrics.spacingS) {
        Text(verbatim: tool).font(.headline)
        StatusBadge(Self.status(of: model.state), Self.label(of: model.state))
          .lineLimit(1).truncationMode(.middle)
        Spacer(minLength: 0)
        if model.state == .checking { ProgressView().controlSize(.small) }
      }
      Text(reason)
        .foregroundStyle(DesignColor.textSecondary.color)
        .fixedSize(horizontal: false, vertical: true)
      if let detail = Self.detail(of: model.state) {
        Text(verbatim: detail)
          .font(.callout.monospaced())
          .textSelection(.enabled)
          .fixedSize(horizontal: false, vertical: true)
      }
      HStack(spacing: DesignMetrics.spacingM) {
        Link(destination: installURL) { Text(.renderKit("Install…")) }
          .accessible(.installCard(tool, .install), label: .renderKit("Install…"))
        Button {
          Task { await model.recheck() }
        } label: {
          Text(.renderKit("Re-check"))
        }
        .disabled(model.state == .checking)
        .accessible(.installCard(tool, .recheck), label: .renderKit("Re-check"))
      }
    }
    .padding(DesignMetrics.spacingL)
    .frame(maxWidth: .infinity, alignment: .leading)
    .overlay(
      RoundedRectangle(cornerRadius: DesignMetrics.radiusMedium)
        .strokeBorder(DesignColor.textSecondary.color.opacity(0.35)))
  }
}
