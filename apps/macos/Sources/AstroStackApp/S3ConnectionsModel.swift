package import Foundation
internal import Observation
package import RemoteKit

/// Settings › S3 connections as the window shows it (card 0150): the list, the connection being
/// edited, why the last save was refused, and the « Test » line.
///
/// The view reads it; tests drive it (a `.task` never runs offscreen). The network is touched
/// only by `test()`, on the user's click.
@Observable
package final class S3ConnectionsModel {
  /// A connection being added or edited, with the secret as typed (empty = keep the stored one).
  package struct Draft: Equatable {
    /// The fields as edited.
    package var connection: S3Connection
    /// The secret as typed; never filled from the Keychain.
    package var secret: String
    /// Added rather than edited (the secret is then required).
    package let isNew: Bool
  }

  /// What the last « Test » said.
  package enum TestResult: Equatable {
    /// The listing is on its way.
    case running
    /// The bucket answered; `count` objects seen under the prefix (one page at most).
    case ok(count: Int)
    /// The answer, as the service or the system wrote it.
    case failed(String)
    /// The connection has no secret stored.
    case secretMissing
    /// No connection is chosen, or it was removed meanwhile.
    case noConnection
  }

  /// The listing page « Test » reads: enough to say the keys work, never the whole bucket.
  package static let testLimit = 1000

  /// The connections, as stored.
  package private(set) var connections: [S3Connection]
  /// The connection being added or edited, `nil` when none.
  package var draft: Draft?
  /// Why the last save or removal was refused.
  package private(set) var refusal: UserFacingError?
  /// The connection « Test » uses; changing it clears the last result.
  package var testConnection: UUID? { didSet { invalidateTest() } }
  /// The bucket « Test » lists; changing it clears the last result.
  package var testBucket = "" { didSet { invalidateTest() } }
  /// The prefix « Test » lists under; changing it clears the last result.
  package var testPrefix = "" { didSet { invalidateTest() } }
  /// What the last « Test » said about the current choice, `nil` before any.
  package private(set) var testResult: TestResult?
  /// Each connection's secret state, read once per reload (never per render: a Keychain query).
  package private(set) var secretStates: [UUID: S3ConnectionStore.SecretState] = [:]
  /// Bumped whenever the choice changes: a « Test » answering for an older choice is dropped.
  @ObservationIgnored private var testGeneration = 0
  @ObservationIgnored private let store: S3ConnectionStore
  @ObservationIgnored private let makeTransport: () -> HTTPTransport
  /// Made on the first « Test » and kept: one URLSession per model, never one per click.
  @ObservationIgnored private var transport: HTTPTransport?

  /// The model over `store`; `transport` makes the network (URLSession live) on first use.
  package init(
    store: S3ConnectionStore = S3ConnectionStore(),
    transport: @escaping () -> HTTPTransport = { .urlSession() }
  ) {
    self.store = store
    makeTransport = transport
    connections = store.connections
    testConnection = connections.first?.id
  }

  /// Whether connection `id` has its secret in the Keychain (as last read).
  package func hasSecret(_ id: UUID) -> Bool { secretStates[id] == .stored }

  /// Reads each connection's secret state (one Keychain query each): when the section appears
  /// and after a change, never at init — SettingsView builds a model per init, then drops it.
  package func refreshSecretStates() {
    secretStates = Dictionary(
      uniqueKeysWithValues: connections.map { ($0.id, store.secretState($0.id)) })
  }

  private func invalidateTest() {
    testGeneration += 1
    testResult = nil
  }

  // MARK: - Editing

  /// Starts a new connection.
  package func add() {
    refusal = nil
    draft = Draft(
      connection: S3Connection(
        name: "", endpoint: "https://", region: "", pathStyle: false, accessKey: ""),
      secret: "", isNew: true)
  }

  /// Starts editing connection `id`; its secret field starts empty (= keep).
  package func edit(_ id: UUID) {
    guard let connection = store.connection(id) else { return }
    refusal = nil
    draft = Draft(connection: connection, secret: "", isNew: false)
  }

  /// Drops the draft.
  package func cancel() {
    draft = nil
    refusal = nil
  }

  /// Stores the draft; a refusal keeps the draft open with the reason.
  package func save() {
    guard let draft else { return }
    do {
      try store.save(draft.connection, secret: draft.secret)
      self.draft = nil
      refusal = nil
      // New keys or endpoint: the last « Test » no longer speaks for this connection.
      if testConnection == draft.connection.id { invalidateTest() }
      reload()
    } catch {
      refusal = .s3Connection(error)
    }
  }

  /// Removes connection `id` and its secret.
  package func remove(_ id: UUID) {
    do {
      try store.remove(id)
      refusal = nil
      if draft?.connection.id == id { draft = nil }
      reload()
    } catch {
      refusal = .s3Connection(error)
    }
  }

  private func reload() {
    connections = store.connections
    if let id = testConnection, !connections.contains(where: { $0.id == id }) {
      testConnection = nil
      testResult = nil
    }
    if testConnection == nil { testConnection = connections.first?.id }
    refreshSecretStates()
  }

  // MARK: - Test

  /// Whether « Test » can run: a connection, a bucket, nothing running.
  package var canTest: Bool {
    testConnection != nil && !testBucket.trimmingCharacters(in: .whitespaces).isEmpty
      && testResult != .running
  }

  /// Lists one page under the bucket and prefix with the chosen connection's keys; the answer
  /// is kept only if the choice did not change meanwhile.
  package func test() async {
    let generation = testGeneration
    guard let id = testConnection, let connection = store.connection(id) else {
      testResult = .noConnection
      return
    }
    let credentials: S3Credentials
    do {
      guard let stored = try store.credentials(for: id) else {
        testResult = .secretMissing
        return
      }
      credentials = stored
    } catch {
      testResult = .failed(String(localized: UserFacingError.s3Connection(error).message))
      return
    }
    testResult = .running
    let outcome = await list(connection, credentials)
    guard generation == testGeneration else { return }
    testResult = outcome
  }

  private func list(_ connection: S3Connection, _ credentials: S3Credentials) async
    -> TestResult
  {
    let transport = transport ?? makeTransport()
    self.transport = transport
    do {
      let client = S3Client(
        endpoint: try connection.s3Endpoint(), credentials: credentials, transport: transport)
      let objects = try await client.list(
        bucket: testBucket.trimmingCharacters(in: .whitespaces), prefix: testPrefix,
        limit: Self.testLimit)
      return .ok(count: objects.count)
    } catch let error as S3Error {
      // S3's own words, as sent (R2): never a rewording.
      return .failed(error.description)
    } catch {
      return .failed(String(localized: UserFacingError(error).message))
    }
  }
}
