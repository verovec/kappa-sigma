/// A named point of an image's history; its step cannot be deleted while it exists.
package struct ImageSnapshot: Equatable, Sendable {
  /// Row id.
  package let id: Int64
  /// The image it belongs to.
  package let imageID: Int64
  /// The history step it names.
  package let stepID: Int64
  /// The user's name for it, unique per image.
  package let name: String
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64
}
