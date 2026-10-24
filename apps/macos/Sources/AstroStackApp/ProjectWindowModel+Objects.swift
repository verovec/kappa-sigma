internal import Foundation

/// The window's side of the Objects section (card 0130).
extension ProjectWindowModel {
  /// The object the project's stack records (`OBJECT` of its lights), else its header's; nil
  /// when neither names one — the Objects section then guesses nothing (card 0130).
  package var projectObjectName: String? {
    let named = [selectedStack?.object, workspace?.studio.header?.string("OBJECT")]
    return named.compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  /// The target, as the project is named (`M31.astrostack` → `M31`).
  var targetName: String { folder()?.deletingPathExtension().lastPathComponent ?? "" }

  /// What a stack's Studio is named after: its object, else the project.
  func studioObject(_ object: String) -> String {
    object.isEmpty ? targetName : object
  }
}
