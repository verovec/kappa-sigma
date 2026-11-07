package import Foundation

/// Where an S3-compatible service answers: AWS, MinIO, Scaleway, Backblaze B2, R2, Garage.
package struct S3Endpoint: Sendable, Equatable {
  /// How a bucket is named in a request.
  package enum Addressing: Sendable {
    /// `https://host/<bucket>/<key>`: MinIO, Garage and most self-hosted servers.
    case pathStyle
    /// `https://<bucket>.host/<key>`: AWS (path-style is deprecated there), R2, Scaleway.
    case virtualHost
  }

  /// `http` or `https`.
  package let scheme: String
  /// The host with its port when not the scheme's default (`127.0.0.1:9000`).
  package let host: String
  /// The signing region (`us-east-1` for MinIO's default, `auto` for R2).
  package let region: String
  /// How buckets are addressed.
  package let addressing: Addressing

  /// Reads scheme, host and port of `url` (its path is ignored); throws `invalidEndpoint` when
  /// the scheme is not http(s) or the host is missing.
  package init(url: URL, region: String, addressing: Addressing) throws {
    guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
      let name = url.host(percentEncoded: false), !name.isEmpty
    else { throw S3Error.invalidEndpoint(url.absoluteString) }
    let defaultPort = scheme == "https" ? 443 : 80
    // An IPv6 literal keeps its brackets in a URL and in `Host`.
    let host = name.contains(":") ? "[\(name)]" : name
    self.scheme = scheme
    self.host = url.port.map { $0 == defaultPort ? host : "\(host):\($0)" } ?? host
    self.region = region
    self.addressing = addressing
  }

  /// The `Host` and decoded path of `key` in `bucket` (`key` empty = the bucket itself).
  package func location(bucket: String, key: String) -> (host: String, path: String) {
    switch addressing {
    case .pathStyle: (host, key.isEmpty ? "/\(bucket)" : "/\(bucket)/\(key)")
    case .virtualHost: ("\(bucket).\(host)", "/\(key)")
    }
  }

  // MARK: - Bucket names (card 0184)

  /// Throws `S3Error.invalidBucket` when `bucket` cannot be addressed here, before any request.
  ///
  /// Path-style is left as permissive as the server (MinIO and Garage accept names AWS refuses):
  /// only an empty name or a `/`, which would address another path, is refused. Virtual-host puts
  /// the name in the host, so it must be a host name (3–63 of `a-z 0-9 . -`, no edge hyphen or
  /// dot, no `..`), and a dotted name over https fails TLS: `*.host` covers one label only.
  package func validate(bucket: String) throws {
    if bucket.isEmpty {
      throw S3Error.invalidBucket(name: bucket, reason: "a bucket name is required")
    }
    if bucket.contains("/") {
      throw S3Error.invalidBucket(name: bucket, reason: "a bucket name has no /")
    }
    guard addressing == .virtualHost else { return }
    let pathStyle = "turn path-style addressing on for this connection"
    if !Self.isHostLabel(bucket) {
      throw S3Error.invalidBucket(
        name: bucket, reason: "not a host name, which virtual-host addressing needs: \(pathStyle)")
    }
    if scheme == "https", bucket.contains(".") {
      throw S3Error.invalidBucket(
        name: bucket,
        reason: "a dot in the name breaks HTTPS with virtual-host addressing: \(pathStyle)")
    }
  }

  /// A bucket name usable as the first labels of a host name.
  private static func isHostLabel(_ name: String) -> Bool {
    let allowed = Set("abcdefghijklmnopqrstuvwxyz0123456789.-")
    guard (3...63).contains(name.count), name.allSatisfy(allowed.contains) else { return false }
    return name.split(separator: ".", omittingEmptySubsequences: false).allSatisfy { label in
      !label.isEmpty && label.first != "-" && label.last != "-"
    }
  }
}
