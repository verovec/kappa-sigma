package import Foundation
internal import ProcessKit
package import ProjectKit
package import RemoteKit

// MARK: - The S3 copy (card 0152)

/// An export's S3 copy, checked: the client, the target and the folder's key under it.
struct RemotePlan {
  /// The connection's client.
  let client: S3Client
  /// Where the copy goes.
  let target: S3Target
  /// The folder's key: the target's prefix plus the template's folders.
  let key: String

  /// `s3://bucket/key`, as shown and recorded.
  var url: String { target.url(key) }

  /// The key of file `name` in the folder.
  func objectKey(_ name: String) -> String {
    key.isEmpty ? name : "\(key)/\(name)"
  }
}

/// How an S3 copy ended.
enum UploadOutcome: Equatable {
  /// No S3 target.
  case none
  /// Every file is there.
  case done
  /// The service's (or the system's) words for the failure.
  case failed(String)
  /// The user stopped it.
  case cancelled

  /// The copy failed (not stopped by the user).
  var isFailure: Bool {
    if case .failed = self { true } else { false }
  }
}

extension ExportStageModel {
  /// The `s3://` folder the next export's copy goes to, as written; `nil` without an S3 target
  /// or while the template names no folder.
  package var remoteFolder: String? {
    guard let s3 = s3?.trimmed,
      let folders = try? ExportPathTemplate(template).components(templateValues)
    else { return nil }
    return s3.url(s3.key(folders))
  }

  /// The S3 side's checks: a bucket, never a capture prefix (R7), the connection and its keys,
  /// no object already at a file's key. `nil` with `failure` set when one refuses.
  func remotePlan(_ typed: S3Target, names: [String]) async -> RemotePlan? {
    let s3 = typed.trimmed
    guard !s3.bucket.isEmpty else {
      failure = .exportS3(.noBucket)
      return nil
    }
    let folders: [String]
    do { folders = try ExportPathTemplate(template).components(templateValues) } catch {
      failure = .exportTemplate(error)
      return nil
    }
    let key = s3.key(folders)
    let location = RemoteLocation(bucket: s3.bucket, prefix: key)
    guard ExportGuard.remoteRefusal(location, sources: services.remoteSources()) == nil else {
      failure = .exportS3(.captureBucket(s3.url(key)))
      return nil
    }
    guard let client = await client(s3.connectionID) else { return nil }
    let plan = RemotePlan(client: client, target: s3, key: key)
    // Said on the stage only once the plan holds: a plan that fails uploads nothing.
    var unchecked = false
    for name in names {
      do {
        if try await client.head(bucket: s3.bucket, key: plan.objectKey(name)) != nil {
          failure = .exportWouldOverwrite(path: s3.url(plan.objectKey(name)))
          return nil
        }
      } catch S3Error.service(403, _, _, _) {
        // A write-only key (the export key Settings recommends) may not read: S3 answers 403
        // for a missing object then. Nothing can be told here — said on the stage; the upload
        // asks the service never to replace an object (`If-None-Match`, card 0185).
        // The same key cannot see the other names either: one HEAD says it.
        unchecked = true
        break
      } catch  where Self.isCancellation(error) {
        return nil  // the user stopped it: nothing to report
      } catch {
        failure = .exportS3(.service(Self.text(error)))
        return nil
      }
    }
    remoteUnchecked = unchecked
    return plan
  }

  /// The client of connection `id`, or `nil` with `failure` set.
  private func client(_ id: UUID) async -> S3Client? {
    do {
      guard let client = try await services.s3Client(id) else {
        failure = .exportS3(.connectionMissing)
        return nil
      }
      return client
    } catch {
      failure = UserFacingError(error)
    }
    return nil
  }

  /// Uploads `urls` (the very files written) one after another.
  ///
  /// The first failure or a cancel stops it; with `discardPartial`, the objects already sent are
  /// deleted then. The service is asked never to replace an object (`If-None-Match: *`), Resend
  /// included: its refusal is said as the object already there (card 0185). An object this very
  /// copy wrote is recognised by its size and ETag where the key can read it.
  func upload(_ urls: [URL], to remote: RemotePlan?, discardPartial: Bool) async -> UploadOutcome {
    guard let remote else { return .none }
    var sent: [String] = []
    for (index, url) in urls.enumerated() {
      uploadProgress = (index + 1, urls.count)
      let key = remote.objectKey(url.lastPathComponent)
      do {
        try Task.checkCancellation()
        _ = try await remote.client.upload(
          file: url, bucket: remote.target.bucket, key: key, contentType: Self.contentType(url),
          ifNoneMatch: true)
        sent.append(key)
      } catch S3Error.service(412, _, _, _) {
        if discardPartial { await Self.discard(sent, from: remote) }
        let refusal = UserFacingError.exportWouldOverwrite(path: remote.target.url(key))
        return .failed(String(localized: refusal.message))
      } catch {
        if discardPartial { await Self.discard(sent, from: remote) }
        return Self.isCancellation(error) ? .cancelled : .failed(Self.text(error))
      }
    }
    return .done
  }

  /// Deletes `keys` in a task of its own, the export's may be cancelled.
  ///
  /// A failed delete leaves the object: nothing else to do about it here.
  private static func discard(_ keys: [String], from remote: RemotePlan) async {
    guard !keys.isEmpty else { return }
    await Task {
      for key in keys { try? await remote.client.delete(bucket: remote.target.bucket, key: key) }
    }.value
  }

  static func isCancellation(_ error: any Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  /// « Resend to S3 » as a task « Cancel » can stop.
  @discardableResult
  package func startResend(_ record: ProjectExport) -> Task<Void, Never>? {
    guard exportTask == nil else { return nil }
    let task = Task { [weak self] in
      await self?.resend(record)
      self?.exportTask = nil
    }
    exportTask = task
    return task
  }

  /// « Resend to S3 »: uploads the files of `record` kept on this Mac to its folder again.
  ///
  /// Through the connection the export used (recorded), never whichever the form shows now;
  /// the outcome is recorded on the row.
  package func resend(_ record: ProjectExport) async {
    guard !isExporting, let path = record.folder, let url = record.remoteURL,
      let (bucket, key) = Self.split(url)
    else { return }
    guard let connection = record.remoteConnection.flatMap(UUID.init(uuidString:)) else {
      failure = .exportS3(.resendNeedsConnection)
      return
    }
    failure = nil
    remoteUnchecked = false
    // The capture sources may have changed since the export: R7 is judged again.
    let location = RemoteLocation(bucket: bucket, prefix: key)
    guard ExportGuard.remoteRefusal(location, sources: services.remoteSources()) == nil else {
      failure = .exportS3(.captureBucket(url))
      return
    }
    guard let client = await client(connection) else { return }
    isExporting = true
    defer {
      isExporting = false
      uploadProgress = nil
    }
    let target = S3Target(connectionID: connection, bucket: bucket, prefix: "")
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    let outcome = await upload(
      record.files.map(folder.appendingPathComponent),
      to: RemotePlan(client: client, target: target, key: key), discardPartial: false)
    do {
      switch outcome {
      case .failed(let text):
        try store.setRemoteStatus(exportID: record.id, .failed, error: text)
        failure = .exportS3(.uploadFailed(text))
      case .cancelled:
        let text = String(localized: .app("Upload cancelled"))
        try store.setRemoteStatus(exportID: record.id, .failed, error: text)
      case .done, .none:
        try store.setRemoteStatus(exportID: record.id, .done, error: nil)
      }
    } catch {
      failure = UserFacingError(error)
    }
    refresh()
  }

  /// Reads Settings' S3 connections again (card 0177): « S3 connections… » beside the S3 target
  /// opens Settings, and the one added there must be offered when the user comes back.
  package func reloadConnections() {
    let read = services.s3Connections()
    if read != s3Connections { s3Connections = read }
  }

  /// Reads the connections now, then on every element of `changes` (each defaults write in the
  /// app), until cancelled — the form's lifetime.
  package func followSettings<Changes: AsyncSequence>(_ changes: Changes) async {
    await DefaultsChanges.follow(changes) { reloadConnections() }
  }

  /// « Copy S3 URL » of `record`.
  package func copyRemoteURL(_ record: ProjectExport) {
    if let url = record.remoteURL { services.copy(url) }
  }

  /// `s3://bucket/key` as bucket and key.
  package static func split(_ url: String) -> (String, String)? {
    ProjectSource.remoteFolder(of: url).map { ($0.bucket, $0.prefix) }
  }

  /// A failure as the user reads it: S3's own words as sent, else the shared sentence.
  static func text(_ error: any Error) -> String {
    if let error = error as? S3Error { return error.description }
    return String(localized: UserFacingError(error).message)
  }

  /// The object's type from the file's extension (what a browser opening the URL needs).
  package static func contentType(_ url: URL) -> String {
    switch url.pathExtension.lowercased() {
    case "png": "image/png"
    case "tif", "tiff": "image/tiff"
    case "jpg", "jpeg": "image/jpeg"
    case "fits", "fit": "application/fits"
    default: "application/octet-stream"
    }
  }
}
