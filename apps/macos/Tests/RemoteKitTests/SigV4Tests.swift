import Foundation
import RemoteKit
import Testing

/// The signer against the official AWS Signature Version 4 test suite (botocore's copy, Apache-2.0,
/// `Fixtures/sigv4/NOTICE`): each case's raw request (`.req`) must produce its canonical request
/// (`.creq`), string to sign (`.sts`) and `Authorization` header (`.authz`) byte for byte.
@Suite("SigV4 signs like AWS")
struct SigV4Tests {
  /// The suite's fixed signing context.
  static let credentials = S3Credentials(
    accessKey: "AKIDEXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY")

  /// Every committed case (the suite's path-normalisation and multi-line header cases are not
  /// committed: S3 keys are never normalised and RemoteKit never folds header lines).
  static let cases = [
    "get-header-key-duplicate", "get-header-value-order", "get-header-value-trim",
    "get-unreserved", "get-utf8", "get-vanilla", "get-vanilla-empty-query-key",
    "get-vanilla-query", "get-vanilla-query-order-encoded", "get-vanilla-query-order-key",
    "get-vanilla-query-order-key-case", "get-vanilla-query-order-value",
    "get-vanilla-query-unreserved", "get-vanilla-utf8-query", "get-vanilla-with-session-token",
    "post-header-key-case", "post-header-key-sort", "post-header-value-case", "post-vanilla",
    "post-vanilla-empty-query-value", "post-vanilla-query", "post-x-www-form-urlencoded",
    "post-x-www-form-urlencoded-parameters",
  ]

  /// The suite's temporary-credentials case: the token is not in the `.req`, the signer adds it.
  static let sessionTokens = [
    "get-vanilla-with-session-token":
      "6e86291e8372ff2a2260956d9b8aae1d763fbf315fa00fa31553b73ebf194267"
  ]

  @Test("Canonical request, string to sign and Authorization match the suite", arguments: cases)
  func testSuiteVectors(name: String) throws {
    let vector = try SigV4Vector.load(name)
    var request = try vector.request()
    request.headers.removeAll { $0.name.lowercased() == "x-amz-date" }
    let signer = SigV4(
      credentials: S3Credentials(
        accessKey: Self.credentials.accessKey, secretKey: Self.credentials.secretKey,
        sessionToken: Self.sessionTokens[name]),
      region: "us-east-1", service: "service")

    var signed = signer.signed(request, date: SigV4Vector.date)
    let authorization = signed.header("Authorization")
    signed.headers.removeAll { $0.name == "Authorization" }

    #expect(signer.canonicalRequest(signed) == vector.canonicalRequest)
    #expect(signer.stringToSign(signed, date: SigV4Vector.date) == vector.stringToSign)
    #expect(authorization == vector.authorization)
  }

  @Test("Every committed vector is listed in the table")
  func testSuiteVectors_tableCoversFixtures() throws {
    let folder = try #require(
      Bundle.module.url(forResource: "sigv4", withExtension: nil, subdirectory: "Fixtures"))
    let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
      .filter { $0.hasSuffix(".req") }.map { String($0.dropLast(4)) }
    #expect(Set(names) == Set(Self.cases))
  }

  @Test("The signing key is the HMAC chain of the AWS documentation example")
  func testSigningKey_documentationExample() {
    // docs.aws.amazon.com « Examples of how to derive a signing key for Signature Version 4 ».
    let signer = SigV4(
      credentials: S3Credentials(
        accessKey: "AKIDEXAMPLE", secretKey: "wJalrXUtnFEMI/K7MDENG+bPxRfiCYEXAMPLEKEY"),
      region: "us-east-1", service: "iam")
    let key = signer.signingKey(day: "20120215")
    #expect(
      key.hexString == "f4780e2d9f65fa895f9c67b32ce1baf0b0d8a43505a000a1a9e090d414db404d")
  }
}
