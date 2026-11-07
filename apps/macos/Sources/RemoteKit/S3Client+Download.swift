package import Foundation

extension S3Client {
  /// Downloads `key` to `destination` through `<destination>.part`, verifies it, then renames.
  ///
  /// Verified: the size and ETag against `expect` (the listing) when given; the content against
  /// a full-object `x-amz-checksum-sha256`, or else a single-part ETag (its MD5, unless SSE-KMS
  /// or SSE-C). A composite checksum (`…-N`) leaves the size as the only check. Any failure,
  /// cancellation included, leaves neither file behind; an existing `destination` is replaced
  /// (atomically) only on success.
  @concurrent
  package func download(
    bucket: String, key: String, to destination: URL, expect: S3Object?,
    progress: S3ProgressHandler? = nil
  ) async throws -> S3Object {
    let part = destination.appendingPathExtension("part")
    let files = FileManager.default
    try? files.removeItem(at: part)
    do {
      let request = S3Request(
        method: "GET", bucket: bucket, key: key, headers: ["x-amz-checksum-mode": "ENABLED"])
      let response = try await retrying(progress) {
        let http = try prepare(request)
        let total = expect?.size ?? 0
        let answer = try await transport.download(http, part) { bytes in
          progress?(.transferred(bytes: bytes, total: total))
        }
        return try checked(answer, bucket: bucket)
      }
      let object = try verify(part, key: key, response: response, expect: expect)
      if files.fileExists(atPath: destination.path) {
        _ = try files.replaceItemAt(destination, withItemAt: part)
      } else {
        try files.moveItem(at: part, to: destination)
      }
      return object
    } catch {
      try? files.removeItem(at: part)
      throw error
    }
  }

  private func verify(_ file: URL, key: String, response: HTTPResponse, expect: S3Object?)
    throws -> S3Object
  {
    let size = try FileDigest.size(file)
    let etag = response.etag ?? ""
    if let expect {
      guard size == expect.size else {
        throw S3Error.sizeMismatch(key: key, expected: expect.size, actual: size)
      }
      guard etag == expect.etag else {
        throw S3Error.objectChanged(key: key, expectedETag: expect.etag, actualETag: etag)
      }
    }
    let object = S3Object(
      key: key, size: size, etag: etag,
      lastModified: response.headers["last-modified"].flatMap(S3Dates.http))
    if let checksum = response.headers["x-amz-checksum-sha256"], !checksum.contains("-") {
      let actual = try FileDigest.sha256Base64(file)
      guard actual == checksum else {
        throw S3Error.checksumMismatch(key: key, expected: checksum, actual: actual)
      }
    } else if object.isSinglePartETag, Self.etagIsMD5(response.headers) {
      let actual = try FileDigest.md5Hex(file)
      guard actual == etag.lowercased() else {
        throw S3Error.checksumMismatch(key: key, expected: etag, actual: actual)
      }
    }
    return object
  }

  /// SSE-KMS and SSE-C objects carry a 32-hex ETag that is not their MD5 (AWS documents it);
  /// SSE-S3 (`AES256`) and unencrypted ones carry the MD5.
  private static func etagIsMD5(_ headers: [String: String]) -> Bool {
    headers["x-amz-server-side-encryption-customer-algorithm"] == nil
      && headers["x-amz-server-side-encryption"]?.hasPrefix("aws:kms") != true
  }
}
