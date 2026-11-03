package import Foundation

/// One page of a ListObjectsV2 answer.
package struct S3ListPage: Sendable, Equatable {
  /// The objects of this page, in key order.
  package let objects: [S3Object]
  /// The sub-prefixes of this page: empty unless the request carried a delimiter (card 0169).
  package let prefixes: [String]
  /// The token of the next page, `nil` on the last one.
  package let continuationToken: String?

  /// Reads a `<ListBucketResult>` document.
  package static func parse(_ data: Data) throws -> Self {
    let root = try XMLNode.parse(data)
    guard root.name == "ListBucketResult" else {
      throw S3Error.invalidResponse("expected ListBucketResult, got \(root.name)")
    }
    let encoded = root.text("EncodingType") == "url"
    let objects = try root.all("Contents").map { node in
      guard let raw = node.text("Key"), let key = encoded ? Self.decoded(raw) : raw,
        let size = node.text("Size").flatMap({ Int64($0) })
      else { throw S3Error.invalidResponse("listing entry without Key or Size") }
      return S3Object(
        key: key, size: size, etag: S3Object.unquoted(node.text("ETag") ?? ""),
        lastModified: node.text("LastModified").flatMap(S3Dates.iso8601))
    }
    // A folder's name can hold the delimiter itself, percent-encoded like a key.
    let prefixes = try root.all("CommonPrefixes").map { node -> String in
      guard let raw = node.text("Prefix"), let prefix = encoded ? Self.decoded(raw) : raw else {
        throw S3Error.invalidResponse("CommonPrefixes entry without Prefix")
      }
      return prefix
    }
    guard root.text("IsTruncated") == "true" else {
      return Self(objects: objects, prefixes: prefixes, continuationToken: nil)
    }
    // Stopping here would return part of the bucket as if it were all of it (R2).
    guard let token = root.text("NextContinuationToken"), !token.isEmpty else {
      throw S3Error.invalidResponse("truncated listing without NextContinuationToken")
    }
    return Self(objects: objects, prefixes: prefixes, continuationToken: token)
  }

  /// A key as `encoding-type=url` sends it: `+` is a space, `%2B` a plus (form encoding).
  private static func decoded(_ key: String) -> String? {
    key.replacingOccurrences(of: "+", with: " ").removingPercentEncoding
  }
}
