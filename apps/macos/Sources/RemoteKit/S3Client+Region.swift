internal import Foundation

extension S3Client {
  /// The codes a 400 carries when the request was signed for another region than the bucket's.
  static let regionCodes: Set<String> = [
    "AuthorizationHeaderMalformed", "IllegalLocationConstraintException",
  ]

  /// `response` when 2xx, otherwise the S3 error it carries (card 0184).
  ///
  /// When the answer names the bucket's region, the error is `wrongRegion`, which keeps the
  /// service's own answer and adds what to change: the region, or the endpoint.
  func checked(_ response: HTTPResponse, bucket: String) throws -> HTTPResponse {
    guard response.isSuccess else {
      let answer = Self.serviceError(response)
      if let region = Self.bucketRegion(response, answer: answer, connection: endpoint.region) {
        throw S3Error.wrongRegion(
          bucket: bucket, region: region, connection: endpoint.region, host: endpoint.host,
          answer: answer)
      }
      throw answer
    }
    return response
  }

  /// The bucket's region named in `x-amz-bucket-region`, when it explains the failure.
  ///
  /// A 301 always does (another region, or this one on an endpoint that does not serve it); any
  /// other 3xx only for another region (a 307 in the same one is S3's transient redirect while a
  /// new bucket's DNS spreads). A 400 does with a region code, or with no code at all: a HEAD has
  /// no body. A 403 or a 400 `RequestTimeout` carrying the header keep the service's words (the
  /// latter stays retried).
  static func bucketRegion(_ response: HTTPResponse, answer: S3Error, connection: String)
    -> String?
  {
    guard let region = response.headers["x-amz-bucket-region"], !region.isEmpty else {
      return nil
    }
    let elsewhere = region.caseInsensitiveCompare(connection) != .orderedSame
    switch response.status {
    case 301: return region
    case 300..<400: return elsewhere ? region : nil
    case 400:
      guard case .service(_, let code, _, _) = answer else { return nil }
      return elsewhere && (code.map(regionCodes.contains) ?? true) ? region : nil
    default: return nil
    }
  }
}
