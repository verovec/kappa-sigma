package import ProcessKit
package import ProjectKit
package import StackKit

/// The profile Add records for a source (card 0060): `id` nil when the user kept none.
package struct KeptProfile: Equatable, Sendable {
  /// The profile id, `nil` for none.
  package let id: String?

  /// The kept profile `id` (`nil`: none).
  package init(id: String?) {
    self.id = id
  }
}

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

  /// The shipped profiles with the project's user copies over them (card 0060), and the copies
  /// that could not be used with why (the sheet shows them); never fatal to the import.
  package nonisolated static func profiles(store: ProjectStore?) -> (
    profiles: [Profile], rejected: [String: String]
  ) {
    guard let registry = try? ProcessRegistry.standard() else { return (shippedProfiles, [:]) }
    do {
      let library = try ProfileLibrary(
        registry: registry, builtins: shippedProfiles,
        user: { try store?.userProfiles() ?? [:] },
        save: { id, json in try store?.saveUserProfile(id: id, json: json) },
        acceptsKnob: acceptsKnob)
      return (library.profiles, library.rejected)
    } catch {
      // The user copies could not be read at all: the shipped profiles, and the reason shown.
      return (shippedProfiles, ["user_profiles": "\(error)"])
    }
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

  /// What Add records for `request`: nothing for another request than the sheet's, or for a
  /// proposal whose plan is not this request's; else the kept profile (`id` nil: none).
  ///
  /// An explicit pick stands whatever the plan; only the proposed one needs the current plan.
  package func profileToRecord(for request: ImportRequest) -> KeptProfile? {
    guard request == self.request else { return nil }
    switch profileChoice {
    // Nothing proposed is not « none »: it records nothing, keeping what a source already has.
    case .proposed:
      guard planIsCurrent, let proposed = proposal?.proposed else { return nil }
      return KeptProfile(id: proposed.id)
    case .profile(let id): return KeptProfile(id: id)
    case .none: return KeptProfile(id: nil)
    }
  }

  /// Records the user's answer to the proposal.
  package func chooseProfile(_ choice: ProfileChoice) {
    profileChoice = choice
  }
}
