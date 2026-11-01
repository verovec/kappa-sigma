package import Foundation
package import RemoteKit

/// Settings › S3 connections (card 0150): the list as JSON under one defaults key, each secret
/// in a `SecretStore` (the Keychain) under the connection's id.
///
/// Read again at each use, like the other settings. Validation happens on save and a refused
/// connection stores nothing; the network is never touched here (« Test » is explicit, R2).
package nonisolated struct S3ConnectionStore {
  /// Why a connection was not saved.
  package enum Refusal: Error, Equatable {
    /// No name.
    case emptyName
    /// Another connection has this name.
    case duplicateName(String)
    /// Not an `http(s)://host` URL.
    case notAnEndpoint(String)
    /// A URL with a path: S3Endpoint would drop it, so the requests would not go where meant.
    case endpointWithPath(String)
    /// The stored list cannot be read (a newer AstroStack wrote it?): saving would erase it.
    case unreadableList
    /// `http://` anywhere but this Mac: keys would cross the network in the clear.
    case insecureEndpoint(String)
    /// No access key.
    case emptyAccessKey
    /// A new connection without its secret.
    case secretMissing
    /// The Keychain refused (its status, for its own message).
    case keychain(KeychainError)
  }

  /// The defaults key of the list.
  package static let key = "s3Connections"
  /// The region a connection without one signs for (MinIO's default).
  package static let defaultRegion = "us-east-1"
  private static let localHosts: Set<String> = ["localhost", "127.0.0.1", "::1"]

  private let defaults: UserDefaults
  private let secrets: SecretStore

  /// The store over `defaults` and `secrets` (the login Keychain live).
  package init(defaults: UserDefaults = .standard, secrets: SecretStore = .keychain()) {
    self.defaults = defaults
    self.secrets = secrets
  }

  /// Whether a connection's secret is in the store.
  package enum SecretState: Equatable {
    /// Stored.
    case stored
    /// Not stored.
    case missing
    /// The store would not say (a Keychain refusal), with its reason.
    case unreadable(KeychainError)
  }

  /// Every connection, in the order they were added; empty when the list cannot be read.
  package var connections: [S3Connection] { (try? storedList()) ?? [] }

  /// The stored list, a repeated id kept once; an unreadable one is an error, never an empty
  /// list to write over.
  private func storedList() throws(Refusal) -> [S3Connection] {
    guard let text = defaults.string(forKey: Self.key) else { return [] }
    do {
      let list = try JSONDecoder().decode([S3Connection].self, from: Data(text.utf8))
      var seen = Set<UUID>()
      return list.filter { seen.insert($0.id).inserted }
    } catch {
      throw .unreadableList
    }
  }

  /// The connection with `id`, if any.
  package func connection(_ id: UUID) -> S3Connection? { connections.first { $0.id == id } }

  /// Whether the secret of `id` is stored, without reading it.
  package func secretState(_ id: UUID) -> SecretState {
    do {
      return try secrets.contains(id.uuidString) ? .stored : .missing
    } catch {
      return .unreadable(Self.keychainError(error))
    }
  }

  /// The keys of connection `id`; `nil` when the connection or its secret is missing, a Keychain
  /// refusal thrown with its reason (never read as « no secret »).
  package func credentials(for id: UUID) throws(Refusal) -> S3Credentials? {
    guard let connection = connection(id) else { return nil }
    let secret: String?
    do { secret = try secrets.read(id.uuidString) } catch {
      throw .keychain(Self.keychainError(error))
    }
    return secret.map { S3Credentials(accessKey: connection.accessKey, secretKey: $0) }
  }

  private static func keychainError(_ error: any Error) -> KeychainError {
    error as? KeychainError ?? KeychainError(status: -1)
  }

  /// Adds `connection`, or replaces the one with its id, and returns it as stored.
  ///
  /// `secret` empty or `nil` keeps the stored one. The stored connection is trimmed, its region
  /// defaulted.
  @discardableResult
  package func save(_ connection: S3Connection, secret: String?) throws(Refusal) -> S3Connection {
    var list = try storedList()
    let cleaned = try validated(connection, among: list)
    // A pasted secret often carries a newline: invisible in a SecureField, fatal to SigV4.
    let typed = secret?.trimmingCharacters(in: .whitespacesAndNewlines)
    if let typed, !typed.isEmpty {
      do { try secrets.write(cleaned.id.uuidString, typed) } catch {
        throw .keychain(Self.keychainError(error))
      }
    } else {
      switch secretState(cleaned.id) {
      case .stored: break
      case .missing: throw .secretMissing
      case .unreadable(let error): throw .keychain(error)
      }
    }
    if let index = list.firstIndex(where: { $0.id == cleaned.id }) {
      list[index] = cleaned
    } else {
      list.append(cleaned)
    }
    store(list)
    return cleaned
  }

  /// Removes connection `id` and its secret.
  package func remove(_ id: UUID) throws(Refusal) {
    let list = try storedList()
    do { try secrets.delete(id.uuidString) } catch {
      throw .keychain(Self.keychainError(error))
    }
    store(list.filter { $0.id != id })
  }

  // MARK: - Validation

  private func validated(_ connection: S3Connection, among list: [S3Connection]) throws(Refusal)
    -> S3Connection
  {
    var cleaned = connection
    cleaned.name = connection.name.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned.endpoint = connection.endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned.accessKey = connection.accessKey.trimmingCharacters(in: .whitespacesAndNewlines)
    let region = connection.region.trimmingCharacters(in: .whitespacesAndNewlines)
    cleaned.region = region.isEmpty ? Self.defaultRegion : region
    guard !cleaned.name.isEmpty else { throw .emptyName }
    let taken = list.contains {
      $0.id != cleaned.id && $0.name.lowercased() == cleaned.name.lowercased()
    }
    guard !taken else { throw .duplicateName(cleaned.name) }
    try Self.checkEndpoint(cleaned)
    guard !cleaned.accessKey.isEmpty else { throw .emptyAccessKey }
    return cleaned
  }

  /// RemoteKit's own endpoint rule, plus two of Settings: no path (it would be dropped) and
  /// `http` only on this Mac.
  private static func checkEndpoint(_ connection: S3Connection) throws(Refusal) {
    let text = connection.endpoint
    guard let endpoint = try? connection.s3Endpoint(), let url = URL(string: text) else {
      throw .notAnEndpoint(text)
    }
    guard ["", "/"].contains(url.path(percentEncoded: true)), url.query() == nil,
      url.fragment() == nil
    else { throw .endpointWithPath(text) }
    // `https://key:secret@host` would put a secret in the plain-text defaults.
    guard url.user() == nil, url.password() == nil else { throw .notAnEndpoint(text) }
    let host = (url.host(percentEncoded: false) ?? "").lowercased()
    guard endpoint.scheme == "https" || localHosts.contains(host) else {
      throw .insecureEndpoint(text)
    }
  }

  private func store(_ list: [S3Connection]) {
    // JSON text, not data: the plist stays readable (and checkably free of secrets). Encoding
    // plain strings, a bool and a UUID cannot fail.
    let encoder = JSONEncoder()
    encoder.outputFormatting = .sortedKeys
    if let data = try? encoder.encode(list), let text = String(bytes: data, encoding: .utf8) {
      defaults.set(text, forKey: Self.key)
    }
  }
}
