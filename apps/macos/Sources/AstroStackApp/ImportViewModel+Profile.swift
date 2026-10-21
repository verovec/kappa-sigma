package import ProcessKit

/// How the user answered the profile proposal (card 0060).
package enum ProfileChoice: Equatable, Sendable {
  /// The proposed profile, if any.
  case proposed
  /// This profile, by id.
  case profile(String)
  /// No profile.
  case none

  /// The project setting holding the profile kept at import (`""`: none).
  package static let settingKey = "import.profile"
}

extension ImportViewModel {
  /// The shipped profiles, read once (an unreadable resource leaves the list empty: the sheet
  /// proposes nothing rather than fail the import).
  nonisolated static let shippedProfiles: [Profile] = {
    guard let registry = try? ProcessRegistry.standard() else { return [] }
    return (try? ProfileLibrary.builtins(registry: registry)) ?? []
  }()

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
