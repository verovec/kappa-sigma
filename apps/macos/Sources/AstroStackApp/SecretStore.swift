internal import Foundation
internal import Synchronization

/// Where secrets go (card 0150): the Keychain live (`keychain(service:)`), memory in tests.
///
/// A struct of closures keyed by account (the connection id); never a log line, never the
/// defaults.
package nonisolated struct SecretStore: Sendable {
  /// The secret of an account, `nil` when none is stored.
  package let read: @Sendable (_ account: String) throws -> String?
  /// Whether an account has a secret, without reading it (no Keychain prompt for the bytes).
  package let contains: @Sendable (_ account: String) throws -> Bool
  /// Stores (or replaces) the secret of an account.
  package let write: @Sendable (_ account: String, _ secret: String) throws -> Void
  /// Removes the secret of an account; removing a missing one is not an error.
  package let delete: @Sendable (_ account: String) throws -> Void

  /// A store from its three calls.
  package init(
    read: @escaping @Sendable (String) throws -> String?,
    contains: @escaping @Sendable (String) throws -> Bool,
    write: @escaping @Sendable (String, String) throws -> Void,
    delete: @escaping @Sendable (String) throws -> Void
  ) {
    self.read = read
    self.contains = contains
    self.write = write
    self.delete = delete
  }

  /// A store in memory, empty, for tests and previews.
  package static func inMemory() -> Self {
    let secrets = Mutex<[String: String]>([:])
    return Self(
      read: { account in secrets.withLock { $0[account] } },
      contains: { account in secrets.withLock { $0[account] != nil } },
      write: { account, secret in secrets.withLock { $0[account] = secret } },
      delete: { account in _ = secrets.withLock { $0.removeValue(forKey: account) } })
  }
}
