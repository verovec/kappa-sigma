/// One « Export » of the Export stage (card 0091): which image and history head, where, with
/// which settings, and the files it wrote.
package struct ProjectExport: Equatable, Sendable, Identifiable {
  /// Row id.
  package let id: Int64
  /// The stack the image belongs to.
  package let stackID: Int64
  /// The image exported.
  package let imageID: Int64
  /// The history step that was the image's head (`nil`: the original, or a step since deleted).
  package let headStepID: Int64?
  /// The absolute folder the files were written into.
  package let folder: String
  /// The export settings, as JSON (ProcessKit's `ExportSettings`; ProjectKit never decodes it).
  package let settingsJSON: String
  /// The file names written, in write order.
  package let files: [String]
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64

  /// An export row.
  package init(
    id: Int64, stackID: Int64, imageID: Int64, headStepID: Int64?, folder: String,
    settingsJSON: String, files: [String], createdAt: Int64, updatedAt: Int64
  ) {
    self.id = id
    self.stackID = stackID
    self.imageID = imageID
    self.headStepID = headStepID
    self.folder = folder
    self.settingsJSON = settingsJSON
    self.files = files
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
