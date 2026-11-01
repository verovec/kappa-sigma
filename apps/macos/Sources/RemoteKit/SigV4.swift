internal import CryptoKit
package import Foundation

/// AWS Signature Version 4 (`AWS4-HMAC-SHA256`), header form: a pure function of the request,
/// the credentials and the signing time.
///
/// The path is encoded once and never normalised, as S3 requires (the generic AWS rule encodes
/// twice and resolves `.`/`..`; S3 keys may legitimately contain both). Every header passed in is
/// signed. Pinned by the AWS test suite (`SigV4Tests`).
package struct SigV4: Sendable {
  /// The `Authorization` scheme.
  package static let algorithm = "AWS4-HMAC-SHA256"

  /// The keys signed with.
  package let credentials: S3Credentials
  /// The region of the scope (`us-east-1` for MinIO's default, `auto` for R2).
  package let region: String
  /// The service of the scope (`s3`).
  package let service: String

  /// Creates a signer for one region and service.
  package init(credentials: S3Credentials, region: String, service: String = "s3") {
    self.credentials = credentials
    self.region = region
    self.service = service
  }

  // MARK: - Steps

  /// Step 1: method, encoded path, sorted query, canonical headers, signed headers, payload hash.
  package func canonicalRequest(_ request: SignableRequest) -> String {
    let headers = Self.canonicalHeaders(request.headers)
    return [
      request.method,
      URIEncoding.encode(request.path, keepingSlash: true),
      Self.canonicalQuery(request.query),
      headers.map { "\($0.name):\($0.value)\n" }.joined(),
      headers.map(\.name).joined(separator: ";"),
      request.payloadHash,
    ].joined(separator: "\n")
  }

  /// Step 2: algorithm, timestamp, scope and the hash of the canonical request.
  package func stringToSign(_ request: SignableRequest, date: Date) -> String {
    [
      Self.algorithm, Self.timestamp(date), scope(day: Self.day(date)),
      Data(canonicalRequest(request).utf8).sha256Hex,
    ].joined(separator: "\n")
  }

  /// Step 3: the `Authorization` header value.
  package func authorization(_ request: SignableRequest, date: Date) -> String {
    let day = Self.day(date)
    let key = SymmetricKey(data: signingKey(day: day))
    let signature = HMAC<SHA256>.authenticationCode(
      for: Data(stringToSign(request, date: date).utf8), using: key)
    let signed = Self.canonicalHeaders(request.headers).map(\.name).joined(separator: ";")
    return "\(Self.algorithm) Credential=\(credentials.accessKey)/\(scope(day: day)), "
      + "SignedHeaders=\(signed), Signature=\(signature.hexString)"
  }

  /// `request` with `x-amz-date` (and the session token) added, then `Authorization`.
  package func signed(_ request: SignableRequest, date: Date) -> SignableRequest {
    var request = request
    request.headers.append(.init("x-amz-date", Self.timestamp(date)))
    if let token = credentials.sessionToken {
      request.headers.append(.init("x-amz-security-token", token))
    }
    request.headers.append(.init("Authorization", authorization(request, date: date)))
    return request
  }

  /// The HMAC-SHA256 chain `AWS4<secret>` → day → region → service → `aws4_request`.
  package func signingKey(day: String) -> Data {
    var key = Data("AWS4\(credentials.secretKey)".utf8)
    for part in [day, region, service, "aws4_request"] {
      key = Data(
        HMAC<SHA256>.authenticationCode(for: Data(part.utf8), using: SymmetricKey(data: key)))
    }
    return key
  }

  // MARK: - Canonical forms

  private func scope(day: String) -> String { "\(day)/\(region)/\(service)/aws4_request" }

  /// Lowercased names sorted, a repeated name's values joined with `,` in sending order, each
  /// value trimmed with inner runs of spaces collapsed.
  private static func canonicalHeaders(_ headers: [SignableRequest.Header])
    -> [(name: String, value: String)]
  {
    var values: [String: [String]] = [:]
    for header in headers {
      values[header.name.lowercased(), default: []].append(trimmed(header.value))
    }
    return values.keys.sorted().map { ($0, values[$0, default: []].joined(separator: ",")) }
  }

  private static func trimmed(_ value: String) -> String {
    value.split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
  }

  /// Names and values encoded, sorted by name then value, `name=value` joined with `&`.
  package static func canonicalQuery(_ query: [SignableRequest.QueryItem]) -> String {
    let encoded: [(name: String, value: String)] = query.map {
      (URIEncoding.encode($0.name), URIEncoding.encode($0.value))
    }
    let sorted = encoded.sorted { lhs, rhs in
      lhs.name == rhs.name ? lhs.value < rhs.value : lhs.name < rhs.name
    }
    return sorted.map { "\($0.name)=\($0.value)" }.joined(separator: "&")
  }

  // MARK: - Time

  /// `YYYYMMDD'T'HHMMSS'Z'` in UTC.
  package static func timestamp(_ date: Date) -> String {
    let parts = utc.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
    let time: [String] = [parts.hour, parts.minute, parts.second].map(pad2)
    return "\(day(parts))T\(time.joined())Z"
  }

  /// `YYYYMMDD` in UTC, the scope's day.
  package static func day(_ date: Date) -> String {
    day(utc.dateComponents([.year, .month, .day], from: date))
  }

  private static func day(_ parts: DateComponents) -> String {
    String(parts.year ?? 0) + pad2(parts.month) + pad2(parts.day)
  }

  private static func pad2(_ value: Int?) -> String {
    let value = value ?? 0
    return value < 10 ? "0\(value)" : "\(value)"
  }

  private static let utc: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    return calendar
  }()
}
