package import Foundation
package import ProcessKit
internal import RenderKit
package import SwiftUI

/// The Import sheet's profile box (card 0060).
///
/// The proposal with its reasons, the user's pick (another profile, or none), and the chosen
/// profile's values with their « why » on hover. Nothing is applied here: Add records the choice.
package struct ImportProfileView: View {
  let model: ImportViewModel
  @Environment(\.locale) private var locale

  /// The profile box of `model`.
  package init(model: ImportViewModel) {
    self.model = model
  }

  package var body: some View {
    GroupBox {
      VStack(alignment: .leading, spacing: DesignMetrics.spacingS) {
        proposalLine
        picker
        if let profile = model.selectedProfile { values(of: profile) }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    } label: {
      Text(.app("Profile"))
    }
  }

  @ViewBuilder private var proposalLine: some View {
    if let proposal = model.proposal, let proposed = proposal.proposed {
      Text(.app("Proposed: \(proposed.title.text(language: language))"))
      Text(
        verbatim: proposal.reasons.map { String(localized: Self.words(for: $0, locale: locale)) }
          .joined(separator: " · ")
      )
      .font(.caption).foregroundStyle(DesignColor.textSecondary.color)
    } else {
      Text(.app("No profile is proposed: pick one, or none."))
        .foregroundStyle(DesignColor.textSecondary.color)
    }
  }

  private var picker: some View {
    Picker(
      selection: Binding(
        get: { model.selectedProfile?.id ?? "" },
        set: { model.chooseProfile($0.isEmpty ? .none : .profile($0)) })
    ) {
      Text(.app("No profile")).tag("")
      ForEach(model.profiles, id: \.id) { profile in
        Text(verbatim: profile.title.text(language: language)).tag(profile.id)
      }
    } label: {
      Text(.app("Profile"))
    }
    .accessible(.importProfile, label: .app("Profile"))
  }

  /// Each value the profile sets, its « why » as the tooltip.
  private func values(of profile: Profile) -> some View {
    VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
      ForEach(Array(profile.steps.enumerated()), id: \.offset) { _, step in
        ForEach(step.values.keys.sorted(), id: \.self) { id in
          Text(verbatim: Self.line(step, id, locale: locale))
            .font(.caption.monospacedDigit())
            .help(Text(verbatim: step.why[id]?.text(language: language) ?? ""))
        }
      }
    }
  }

  private var language: String { AppLocale.language(of: locale) }

  /// « Process · Parameter = value », titles from ProcessKit's catalog in `locale`.
  nonisolated static func line(_ step: Profile.Step, _ id: String, locale: Locale) -> String {
    let type = (try? ProcessRegistry.standard())?.type(id: step.recipe.processID)
    let process = type.map { title($0.title, locale) } ?? step.recipe.processID
    let parameter = type?.schema.spec(id).map { title($0.title, locale) } ?? id
    return "\(process) · \(parameter) = \(text(step.values[id], locale))"
  }

  private nonisolated static func title(_ key: String, _ locale: Locale) -> String {
    String(localized: ProcessKitResources.title(key, locale: locale))
  }

  /// A value as the panel writes it, numbers in `locale` (« 0,115 »).
  nonisolated static func text(_ value: ParamValue?, _ locale: Locale) -> String {
    switch value {
    case .number(let number): AstroFormat(locale: locale).parameter(number)
    case .flag(let flag): flag ? "✓" : "✗"
    case .choice(let option): option
    case .points(let points): "\(points.count)"
    case nil: ""
    }
  }

  /// Why the profile is proposed, in `locale`.
  package nonisolated static func words(
    for reason: ProfileProposal.Reason, locale: Locale? = nil
  ) -> LocalizedStringResource {
    switch reason {
    case .camera(.osc): .app("One-shot colour camera", locale: locale)
    case .camera(.mono): .app("Mono camera", locale: locale)
    case .filters(let filters): words(for: filters, locale: locale)
    case .object(let name): .app("Validated on \(name)", locale: locale)
    case .onlyMatch: .app("The only profile for these captures", locale: locale)
    }
  }

  private nonisolated static func words(
    for filters: Profile.Filters, locale: Locale?
  ) -> LocalizedStringResource {
    switch filters {
    case .broadband: .app("Broadband nights", locale: locale)
    case .dualband: .app("Dual-band nights only", locale: locale)
    case .broadbandDualband: .app("Broadband and dual-band nights", locale: locale)
    case .lrgb: .app("L, R, G, B filters", locale: locale)
    case .lrgbHa: .app("L, R, G, B and Hα filters", locale: locale)
    case .narrowband: .app("Narrowband filters", locale: locale)
    }
  }
}
