package import Foundation
internal import ProjectKit

/// What the window names after the project or a stack.
extension ProjectWindowModel {
  /// The target, as the project is named (`M31.astrostack` → `M31`).
  package var targetName: String { folder().map(ProjectPackage.target(of:)) ?? "" }

  /// What a stack's Studio is named after: its object, else the project.
  func studioObject(_ object: String) -> String {
    object.isEmpty ? targetName : object
  }
}

extension ProjectWindowModel {
  /// The head of a project window (card 0146): its target, the package it shows and that
  /// package's path key (`WelcomeModel.key`, resolved once here — the switcher checks its entry
  /// by it).
  package struct Head: Equatable, Sendable {
    /// The target the project is named after; empty for an untitled window.
    package let target: String
    /// The package shown; `nil` for an untitled window.
    package let current: URL?
    /// The path key of the package shown, resolved once.
    package let key: String?

    package init(target: String, current: URL?) {
      self.target = target
      self.current = current
      key = current.map(WelcomeModel.key)
    }
  }
}
