internal import Foundation
internal import Security

/// A Keychain call that failed: its `OSStatus`, shown with the system's own message.
package nonisolated struct KeychainError: Error, Equatable {
  /// The `OSStatus` the Security framework returned.
  package let status: Int32

  /// The error of `status`.
  package init(status: Int32) { self.status = status }

  /// The system's sentence for the status (« The user name or passphrase you entered is not
  /// correct. »), or the bare number.
  package var message: String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
  }
}

nonisolated extension SecretStore {
  /// The service the app's S3 secrets are filed under in the login Keychain.
  package static let s3Service = "AstroStack.S3"

  /// Generic passwords in the login Keychain, `service` + account (the connection id).
  package static func keychain(service: String = s3Service) -> Self {
    Self(
      read: { account in try Keychain.read(service: service, account: account) },
      contains: { account in try Keychain.contains(service: service, account: account) },
      write: { account, secret in
        try Keychain.write(service: service, account: account, secret: secret)
      },
      delete: { account in try Keychain.delete(service: service, account: account) })
  }
}

/// The four SecItem calls, generic-password class only.
private nonisolated enum Keychain {
  static func query(service: String, account: String) -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
      kSecAttrAccount as String: account,
    ]
  }

  static func read(service: String, account: String) throws -> String? {
    var query = query(service: service, account: account)
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess, let data = item as? Data else {
      throw KeychainError(status: status)
    }
    return String(bytes: data, encoding: .utf8)
  }

  /// Attributes only: whether the item exists, its secret never fetched.
  static func contains(service: String, account: String) throws -> Bool {
    let status = SecItemCopyMatching(query(service: service, account: account) as CFDictionary, nil)
    if status == errSecItemNotFound { return false }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    return true
  }

  static func write(service: String, account: String, secret: String) throws {
    let query = query(service: service, account: account)
    let value = [kSecValueData as String: Data(secret.utf8)]
    var status = SecItemUpdate(query as CFDictionary, value as CFDictionary)
    if status == errSecItemNotFound {
      status = SecItemAdd(query.merging(value) { $1 } as CFDictionary, nil)
    }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
  }

  static func delete(service: String, account: String) throws {
    let status = SecItemDelete(query(service: service, account: account) as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError(status: status)
    }
  }
}
