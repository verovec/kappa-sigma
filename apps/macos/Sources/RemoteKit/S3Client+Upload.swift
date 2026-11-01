package import Foundation

extension S3Client {
  /// Uploads `file` to `key`, in parts from `policy.multipartThreshold` on.
  ///
  /// One PUT below the threshold, otherwise a multipart upload in `policy.partSize` parts. Every
  /// body carries `x-amz-checksum-sha256`, so the service rejects a corrupted part. A failed or
  /// cancelled multipart upload is aborted.
  @concurrent
  package func upload(
    file: URL, bucket: String, key: String, contentType: String = "application/octet-stream",
    progress: S3ProgressHandler? = nil
  ) async throws -> S3Object {
    let size = try FileDigest.size(file)
    // Without it URLSession labels every body `application/x-www-form-urlencoded`.
    let type = ["content-type": contentType]
    guard size >= policy.multipartThreshold else {
      let body = try Data(contentsOf: file)
      let digest = body.sha256Digests
      let response = try await perform(
        S3Request(
          method: "PUT", bucket: bucket, key: key,
          headers: type.merging(["x-amz-checksum-sha256": digest.base64]) { $1 }, body: body,
          payloadHash: digest.hex),
        progress: progress)
      let sent = Int64(body.count)
      progress?(.transferred(bytes: sent, total: sent))
      return S3Object(key: key, size: sent, etag: response.etag ?? "", lastModified: nil)
    }
    return try await multipart(
      file: file, size: size, bucket: bucket, key: key, headers: type, progress: progress)
  }

  /// One uploaded part, as CompleteMultipartUpload lists it.
  private struct Part {
    let number: Int
    let etag: String
    let checksum: String
  }

  private func multipart(
    file: URL, size: Int64, bucket: String, key: String, headers: [String: String],
    progress: S3ProgressHandler?
  ) async throws -> S3Object {
    let initiated = try await perform(
      S3Request(
        method: "POST", bucket: bucket, key: key, query: [.init("uploads", "")],
        headers: headers.merging(["x-amz-checksum-algorithm": "SHA256"]) { $1 }))
    guard let uploadID = try XMLNode.parse(initiated.body).text("UploadId") else {
      throw S3Error.invalidResponse("CreateMultipartUpload without UploadId")
    }
    do {
      // The size is what was read, not the earlier stat: a file still being written changes.
      let (parts, sent) = try await uploadParts(
        file: file, size: size, bucket: bucket, key: key, uploadID: uploadID, progress: progress)
      return try await complete(
        bucket: bucket, key: key, uploadID: uploadID, parts: parts, size: sent,
        progress: progress)
    } catch {
      await abort(bucket: bucket, key: key, uploadID: uploadID)
      throw error
    }
  }

  /// CompleteMultipartUpload, retried; it may answer 200 and still fail in its body, and an
  /// InternalError there is retried like a 500 with the parts kept.
  private func complete(
    bucket: String, key: String, uploadID: String, parts: [Part], size: Int64,
    progress: S3ProgressHandler?
  ) async throws -> S3Object {
    let request = S3Request(
      method: "POST", bucket: bucket, key: key, query: [.init("uploadId", uploadID)],
      headers: ["content-type": "application/xml"], body: Self.completion(parts))
    do {
      let root = try await retrying(progress) {
        let response = try await send(request)
        let root = try XMLNode.parse(response.body)
        if root.name == "Error" { throw Self.serviceError(response) }
        return root
      }
      let etag = S3Object.unquoted(root.text("ETag") ?? "")
      return S3Object(key: key, size: size, etag: etag, lastModified: nil)
    } catch S3Error.service(404, "NoSuchUpload", let message, let requestID) {
      // A try whose answer was lost may have completed the upload: the retry then finds no
      // upload. The object, if whole (same size, as many parts), is the result.
      if let object = try await head(bucket: bucket, key: key), object.size == size,
        object.etag.hasSuffix("-\(parts.count)")
      {
        return object
      }
      throw S3Error.service(
        status: 404, code: "NoSuchUpload", message: message, requestID: requestID)
    }
  }

  /// Every part until the end of the file, with the bytes sent; `size` is the progress total.
  private func uploadParts(
    file: URL, size: Int64, bucket: String, key: String, uploadID: String,
    progress: S3ProgressHandler?
  ) async throws -> (parts: [Part], sent: Int64) {
    let handle = try FileHandle(forReadingFrom: file)
    defer { try? handle.close() }
    var parts: [Part] = []
    var sent: Int64 = 0
    while true {
      try Task.checkCancellation()
      let body = try handle.read(upToCount: policy.partSize) ?? Data()
      guard !body.isEmpty else { break }
      let number = parts.count + 1
      let digest = body.sha256Digests
      let response = try await perform(
        S3Request(
          method: "PUT", bucket: bucket, key: key,
          query: [.init("partNumber", String(number)), .init("uploadId", uploadID)],
          headers: ["x-amz-checksum-sha256": digest.base64], body: body, payloadHash: digest.hex),
        progress: progress)
      // Completing with an empty ETag would fail later as an opaque InvalidPart.
      guard let etag = response.etag, !etag.isEmpty else {
        throw S3Error.invalidResponse("UploadPart \(number) of \(key) without ETag")
      }
      parts.append(Part(number: number, etag: etag, checksum: digest.base64))
      sent += Int64(body.count)
      progress?(.transferred(bytes: sent, total: max(size, sent)))
    }
    return (parts, sent)
  }

  /// Aborts the multipart upload `uploadID`, in its own task.
  ///
  /// The caller's task may be cancelled, and a cancelled task's requests fail at once. A failed
  /// abort is logged; the bucket's lifecycle rule is the last resort.
  private func abort(bucket: String, key: String, uploadID: String) async {
    let request = S3Request(
      method: "DELETE", bucket: bucket, key: key, query: [.init("uploadId", uploadID)])
    let client = self
    let outcome = await Task { try await client.perform(request) }.result
    if case .failure(let error) = outcome {
      Self.logger.error("abort of upload \(uploadID) failed: \(String(describing: error))")
    }
  }

  private static func completion(_ parts: [Part]) -> Data {
    let items = parts.map {
      "<Part><PartNumber>\($0.number)</PartNumber><ETag>\"\($0.etag)\"</ETag>"
        + "<ChecksumSHA256>\($0.checksum)</ChecksumSHA256></Part>"
    }
    let xml =
      "<CompleteMultipartUpload xmlns=\"http://s3.amazonaws.com/doc/2006-03-01/\">"
      + items.joined() + "</CompleteMultipartUpload>"
    return Data(xml.utf8)
  }
}
