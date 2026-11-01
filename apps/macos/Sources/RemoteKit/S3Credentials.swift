/// An S3 access key pair, plus the session token of temporary credentials.
///
/// A plain value: where it is stored (the Keychain, card 0150) is not RemoteKit's concern.
package struct S3Credentials: Sendable, Equatable {
  /// The access key id (`AKIA…`), sent in the clear in every `Authorization` header.
  package let accessKey: String
  /// The secret key; only ever used to derive the signing key, never sent.
  package let secretKey: String
  /// The STS session token of temporary credentials, sent as `x-amz-security-token`.
  package let sessionToken: String?

  /// Creates credentials; `sessionToken` only for temporary (STS) credentials.
  package init(accessKey: String, secretKey: String, sessionToken: String? = nil) {
    self.accessKey = accessKey
    self.secretKey = secretKey
    self.sessionToken = sessionToken
  }
}
