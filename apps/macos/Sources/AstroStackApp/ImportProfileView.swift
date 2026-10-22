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
        if !model.rejectedProfiles.isEmpty { rejected }
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

  /// The user copies left out, by id; why on hover.
  private var rejected: some View {
    let ids = model.rejectedProfiles.keys.sorted()
    let reasons = ids.map { "\($0): \(model.rejectedProfiles[$0] ?? "")" }
    return StatusBadge(
      .attention, .app("Saved profiles not offered: \(ids.joined(separator: ", "))")
    )
    .help(Text(verbatim: reasons.joined(separator: "\n")))
  }

  private var picker: some View {
    Picker(
      selection: Binding(
        get: { Self.tag(for: model) },
        set: { model.chooseProfile(Self.choice(for: $0)) })
    ) {
      // « Choose a profile »: the proposal stands, but there is none (or its plan is not current),
      // so Add records nothing — never shown as « No profile », which records none.
      if Self.tag(for: model) == Self.undecided {
        Text(.app("Choose a profile")).tag(Self.undecided)
      }
      Text(.app("No profile")).tag("")
      ForEach(model.profiles, id: \.id) { profile in
        Text(verbatim: profile.title.text(language: language)).tag(profile.id)
      }
    } label: {
      Text(.app("Profile"))
    }
    .accessible(.importProfile, label: .app("Profile"))
  }

  /// The picker's tag of the undecided state.
  package static let undecided = "?"

  /// The picker's tag for the choice of `model`: what Add would record.
  package static func tag(for model: ImportViewModel) -> String {
    switch model.profileChoice {
    case .none: ""
    case .profile(let id): id
    case .proposed: model.selectedProfile?.id ?? undecided
    }
  }

  /// The choice a picker `tag` stands for.
  package nonisolated static func choice(for tag: String) -> ProfileChoice {
    switch tag {
    case "": .none
    case undecided: .proposed
    default: .profile(tag)
    }
  }

  /// Each value the profile sets, with its « ? »: the why on hover, the parameter's definition
  /// and the why on click (card 0086).
  private func values(of profile: Profile) -> some View {
    let registry = try? ProcessRegistry.standard()
    return VStack(alignment: .leading, spacing: DesignMetrics.spacingXXS) {
      ForEach(Array(profile.steps.enumerated()), id: \.offset) { _, step in
        ForEach(step.values.keys.sorted(), id: \.self) { id in
          HStack(spacing: DesignMetrics.spacingXS) {
            Text(verbatim: Self.line(step, id, registry: registry, locale: locale))
              .font(.caption.monospacedDigit())
            let why = step.why[id]?.text(language: language) ?? ""
            HelpButton(
              summary: .app("\(why)"), label: .whyThisValue,
              key: .help("profile.\(step.recipe.processID).\(id)")
            ) {
              HelpText(Self.valueHelp(step.recipe.processID, id, why: why, language: language))
            }
          }
        }
      }
    }
  }

  /// The parameter's definition (HelpKit `params.json`) then the profile's why, one paragraph each.
  package nonisolated static func valueHelp(
    _ process: String, _ param: String, why: String, language: String
  ) -> String {
    let definition = AppGlossary.help.paramDoc(process: process, param: param, locale: language)
    return [definition, why].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
  }

  private var language: String { AppLocale.language(of: locale) }

  /// « Process · Parameter = value », titles from ProcessKit's catalog in `locale`.
  package nonisolated static func line(
    _ step: Profile.Step, _ id: String, registry: ProcessRegistry?, locale: Locale
  ) -> String {
    let type = registry?.type(id: step.recipe.processID)
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
