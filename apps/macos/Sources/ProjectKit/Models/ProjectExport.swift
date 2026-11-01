/// One row of `exports` (cards 0091, 0152): what an « Export » wrote, where, and whether its S3
/// copy arrived.
package struct ProjectExport: Equatable, Sendable, Identifiable {
  /// Where the S3 copy stands (`remote_status`).
  package enum RemoteStatus: String, Equatable, Sendable {
    /// No S3 target.
    case none
    /// Every file uploaded.
    case done
    /// The upload failed; `remoteError` says why, « Resend to S3 » tries again.
    case failed
  }

  /// Row id.
  package let id: Int64
  /// The stack the image belongs to.
  package let stackID: Int64
  /// The image exported.
  package let imageID: Int64
  /// The history step that was the image's head (`nil`: the original, or a step since deleted).
  package let headStepID: Int64?
  /// The absolute folder the files were written into; `nil` for an export sent to S3 only.
  package let folder: String?
  /// The export settings, as JSON (ProcessKit's `ExportSettings`; ProjectKit never decodes it).
  package let settingsJSON: String
  /// The file names written, in write order.
  package let files: [String]
  /// The `s3://bucket/prefix/…` folder the files went to, `nil` without an S3 target.
  package let remoteURL: String?
  /// Where the S3 copy stands.
  package let remoteStatus: RemoteStatus
  /// The service's own words for a failed upload, as sent.
  package let remoteError: String?
  /// The id of the S3 connection the copy went through (« Resend » uses it).
  package let remoteConnection: String?
  /// Creation time, Unix milliseconds.
  package let createdAt: Int64
  /// Last update time, Unix milliseconds.
  package let updatedAt: Int64

  /// An export row; without an S3 target unless `remoteURL` is given.
  package init(
    id: Int64, stackID: Int64, imageID: Int64, headStepID: Int64?, folder: String?,
    settingsJSON: String, files: [String], remoteURL: String? = nil,
    remoteStatus: RemoteStatus = .none, remoteError: String? = nil,
    remoteConnection: String? = nil, createdAt: Int64,
    updatedAt: Int64
  ) {
    self.id = id
    self.stackID = stackID
    self.imageID = imageID
    self.headStepID = headStepID
    self.folder = folder
    self.settingsJSON = settingsJSON
    self.files = files
    self.remoteURL = remoteURL
    self.remoteStatus = remoteStatus
    self.remoteError = remoteError
    self.remoteConnection = remoteConnection
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
