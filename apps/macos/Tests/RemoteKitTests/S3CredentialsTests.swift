import Foundation
import RemoteKit
import Testing

/// Card 0184: credentials never print their secret, wherever they are printed from.
@Suite("S3 credentials print redacted")
struct S3CredentialsTests {
  static let secret = "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  static let token = "FwoGZXIvYXdzEJr//////////wEaDEXAMPLETOKEN"

  struct Row: Sendable, CustomTestStringConvertible {
    let label: String
    let credentials: S3Credentials
    var testDescription: String { label }
  }

  static let rows = [
    Row(
      label: "long-term keys",
      credentials: S3Credentials(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: secret)),
    Row(
      label: "a short key shows nothing of itself",
      credentials: S3Credentials(accessKey: "minio", secretKey: secret)),
    Row(
      label: "temporary keys with a session token",
      credentials: S3Credentials(
        accessKey: "ASIAIOSFODNN7EXAMPLE", secretKey: secret, sessionToken: token)),
  ]

  /// Every way Swift prints a value: interpolation, `String(reflecting:)`, `dump`, and as a
  /// field of the signer and of the client that hold it.
  static func printed(_ credentials: S3Credentials) throws -> [String] {
    let endpoint = try S3Endpoint(
      url: try #require(URL(string: "https://s3.eu-west-3.amazonaws.com")), region: "eu-west-3",
      addressing: .virtualHost)
    let client = S3Client(
      endpoint: endpoint, credentials: credentials, transport: Fake { _, _ in .make(200) }.transport
    )
    let signer = SigV4(credentials: credentials, region: "eu-west-3")
    var dumped = ""
    dump(credentials, to: &dumped)
    var dumpedClient = ""
    dump(client, to: &dumpedClient)
    return [
      "\(credentials)", String(reflecting: credentials), dumped,
      "\(signer)", String(reflecting: signer), "\(client)", String(reflecting: client),
      dumpedClient,
    ]
  }

  @Test(
    "the secret and the session token never print; the access key shows its last 4 characters",
    arguments: rows)
  func testDescriptionRedactsSecrets(row: Row) throws {
    for text in try Self.printed(row.credentials) {
      #expect(!text.contains(Self.secret), "secret in: \(text)")
      #expect(!text.contains(Self.token), "token in: \(text)")
      #expect(!text.contains(row.credentials.accessKey), "whole access key in: \(text)")
    }
    let shown = "\(row.credentials)"
    // The last 4, as the AWS CLI shows them: every AWS key starts AKIA or ASIA.
    if row.credentials.accessKey.count >= 12 {
      #expect(shown.contains("…\(row.credentials.accessKey.suffix(4))"))
    }
    // The access key's field shows at most its last 4, never its first (AKIA/ASIA tell none apart).
    let field = try #require(
      shown.split(separator: "accessKey: ").last?.split(separator: ",").first)
    #expect(!field.contains(row.credentials.accessKey.prefix(4)))
    #expect(field.count <= "…".count + 4 || field == "<redacted>")
    #expect(shown.contains("redacted"))
  }

  @Test("redaction changes printing only: the values still sign")
  func testValuesUnchanged() {
    let credentials = S3Credentials(accessKey: "AKIAIOSFODNN7EXAMPLE", secretKey: Self.secret)
    #expect(credentials.secretKey == Self.secret)
    #expect(credentials.accessKey == "AKIAIOSFODNN7EXAMPLE")
  }
}
