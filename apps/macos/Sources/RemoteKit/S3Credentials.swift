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

// MARK: - Printing (card 0184)

/// Printed, logged or dumped, the credentials show the first 4 characters of the access key and
/// never the secret or the session token: a client or signer printed whole stays safe to share.
extension S3Credentials: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
  /// `S3Credentials(accessKey: AKIA…, secretKey: <redacted>, sessionToken: <redacted>)`.
  package var description: String {
    "S3Credentials(accessKey: \(shownAccessKey), secretKey: \(Self.redacted)"
      + (sessionToken == nil ? ")" : ", sessionToken: \(Self.redacted))")
  }

  /// The same as `description`.
  package var debugDescription: String { description }

  /// The redacted fields, for `dump` and `Mirror`.
  package var customMirror: Mirror {
    var children: [(label: String?, value: Any)] = [
      ("accessKey", shownAccessKey), ("secretKey", Self.redacted),
    ]
    if sessionToken != nil { children.append(("sessionToken", Self.redacted)) }
    return Mirror(self, children: children, displayStyle: .struct)
  }

  private static let redacted = "<redacted>"

  /// Enough to tell two keys apart (AWS shows the same 4 in its console), never the whole key.
  private var shownAccessKey: String { "\(accessKey.prefix(4))…" }
}
