package import ProcessKit
package import ProjectKit
internal import StackKit

/// How the user answered the profile proposal (card 0060).
package enum ProfileChoice: Equatable, Sendable {
  /// The proposed profile, if any.
  case proposed
  /// This profile, by id.
  case profile(String)
  /// No profile.
  case none
}

extension ImportViewModel {
  /// The shipped profiles, read once (an unreadable resource leaves the list empty: the sheet
  /// proposes nothing rather than fail the import).
  package nonisolated static let shippedProfiles: [Profile] = {
    guard let registry = try? ProcessRegistry.standard() else { return [] }
    return (try? ProfileLibrary.builtins(registry: registry)) ?? []
  }()

  /// The shipped profiles with the project's user copies over them (card 0060); a copy that does
  /// not load is left out (the library lists it), never fatal to the import.
  package nonisolated static func profiles(store: ProjectStore?) -> [Profile] {
    guard let registry = try? ProcessRegistry.standard() else { return shippedProfiles }
    let library = try? ProfileLibrary(
      registry: registry, user: { try store?.userProfiles() ?? [:] },
      save: { id, json in try store?.saveUserProfile(id: id, json: json) },
      acceptsKnob: acceptsKnob)
    return library?.profiles ?? shippedProfiles
  }

  /// Whether `id` is a preprocessing knob accepting `value` (StackKit's `KnobSchema`).
  package nonisolated static func acceptsKnob(_ id: String, _ value: ParamValue) -> Bool {
    guard let knob = KnobSchema.knob(id) else { return false }
    let converted: KnobValue? =
      switch value {
      case .number(let number): .number(number)
      case .flag(let flag): .flag(flag)
      case .choice(let option): .choice(option)
      case .points: nil
      }
    return converted.map(knob.accepts) ?? false
  }

  /// The profile the plan's inventory proposes, with its reasons; `nil` before a plan.
  package var proposal: ProfileProposal? {
    plan.map { ProfileProposal.propose(.init(inventory: $0.inventory), among: profiles) }
  }

  /// The profile the user keeps: the proposal until they pick another, or none.
  package var selectedProfile: Profile? {
    switch profileChoice {
    case .proposed: proposal?.proposed
    case .profile(let id): profiles.first { $0.id == id }
    case .none: nil
    }
  }

  /// Records the user's answer to the proposal.
  package func chooseProfile(_ choice: ProfileChoice) {
    profileChoice = choice
  }
}
