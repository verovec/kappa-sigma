internal import Foundation

/// The window's side of the Objects section (card 0130).
extension ProjectWindowModel {
  /// The object the project's stack records (`OBJECT` of its lights), else its header's; nil
  /// when neither names one — the Objects section then guesses nothing (card 0130).
  package var projectObjectName: String? {
    let named = [selectedStack?.object, workspace?.studio.header?.string("OBJECT")]
    return named.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }
  }
}
