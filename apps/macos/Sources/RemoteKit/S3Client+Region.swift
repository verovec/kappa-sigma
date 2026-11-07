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
      if let region = Self.bucketRegion(response, answer: answer) {
        throw S3Error.wrongRegion(
          bucket: bucket, region: region, connection: endpoint.region, host: endpoint.host,
          answer: answer)
      }
      throw answer
    }
    return response
  }

  /// The bucket's region named in `x-amz-bucket-region` by a refused redirect (3xx), or by a 400
  /// whose code says the signing region is wrong.
  ///
  /// Other answers keep the service's words: S3 also sends the header with a 403 or a 400
  /// `RequestTimeout` that have nothing to do with regions (the latter stays retried).
  static func bucketRegion(_ response: HTTPResponse, answer: S3Error) -> String? {
    guard let region = response.headers["x-amz-bucket-region"], !region.isEmpty else {
      return nil
    }
    if (300..<400).contains(response.status) { return region }
    guard response.status == 400, case .service(_, let code?, _, _) = answer,
      regionCodes.contains(code)
    else { return nil }
    return region
  }
}
