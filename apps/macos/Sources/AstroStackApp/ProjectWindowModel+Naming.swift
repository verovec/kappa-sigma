internal import Foundation
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
