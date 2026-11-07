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
  func checked(_ response: HTTPResponse, bucket: String, method: String) throws -> HTTPResponse {
    guard response.isSuccess else {
      let answer = Self.serviceError(response)
      if let region = Self.bucketRegion(
        response, answer: answer, connection: endpoint.region, head: method == "HEAD")
      {
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
  /// A 301 always does (another region, or this one on an endpoint that does not serve it). Any
  /// other answer only when it names another region than the connection's: a 3xx (a 307 in the
  /// same region is S3's transient redirect while a new bucket's DNS spreads), a 400 with a
  /// region code (`AuthorizationHeaderMalformed` in the same region is a malformed key), or a
  /// HEAD's body-less 400. A 403, or a 400 such as `RequestTimeout`, keep the service's words.
  static func bucketRegion(
    _ response: HTTPResponse, answer: S3Error, connection: String, head: Bool
  ) -> String? {
    guard let region = response.headers["x-amz-bucket-region"], !region.isEmpty else {
      return nil
    }
    if response.status == 301 { return region }
    guard region.caseInsensitiveCompare(connection) != .orderedSame else { return nil }
    switch response.status {
    case 300..<400: return region
    case 400:
      guard case .service(_, let code, _, _) = answer else { return nil }
      if let code { return regionCodes.contains(code) ? region : nil }
      return head && response.body.isEmpty ? region : nil
    default: return nil
    }
  }
}
