import AstroStackApp
import Foundation
import RemoteKit
import Testing

/// Settings › S3 connections (card 0150): named connections in the defaults, secrets elsewhere.
@Suite("S3 connections — stored by id, secret never in the defaults")
struct S3ConnectionStoreTests {
  /// A fresh defaults suite and an in-memory secret store, removed at the end.
  struct Fixture {
    let name = "fr.astrostack.tests.s3.\(UUID().uuidString)"
    let defaults: UserDefaults
    let secrets = SecretStore.inMemory()
    var store: S3ConnectionStore { S3ConnectionStore(defaults: defaults, secrets: secrets) }

    init() throws { defaults = try #require(UserDefaults(suiteName: name)) }
    func tearDown() { defaults.removePersistentDomain(forName: name) }
  }

  static func draft(
    _ name: String, endpoint: String = "https://s3.fr-par.scw.cloud", region: String = "fr-par"
  ) -> S3Connection {
    S3Connection(
      name: name, endpoint: endpoint, region: region, pathStyle: false, accessKey: "SCWKEY")
  }

  @Test("add, read back, rename (same id), delete (secret gone)")
  func testAddReadRenameDelete() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }
    let store = fixture.store

    let saved = try store.save(Self.draft("Captures (lecture)"), secret: "s3cr3t")
    #expect(store.connections == [saved])
    #expect(
      try store.credentials(for: saved.id)
        == S3Credentials(accessKey: "SCWKEY", secretKey: "s3cr3t"))
    #expect(store.secretState(saved.id) == .stored)

    var renamed = saved
    renamed.name = "Captures"
    let kept = try store.save(renamed, secret: nil)
    #expect(kept.id == saved.id, "a rename keeps the id sources and exports store")
    #expect(store.connections.map(\.name) == ["Captures"])
    #expect(try store.credentials(for: saved.id)?.secretKey == "s3cr3t", "no secret typed = kept")

    let second = try store.save(Self.draft("Exports"), secret: "w")
    #expect(store.connections.map(\.name) == ["Captures", "Exports"])

    try store.remove(saved.id)
    #expect(store.connections == [second])
    #expect(try store.credentials(for: saved.id) == nil)
    #expect(try fixture.secrets.read(saved.id.uuidString) == nil, "the secret went with it")
  }

  @Test("the defaults plist holds the connection, never its secret")
  func testSecretNeverInDefaults() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }

    let saved = try fixture.store.save(Self.draft("Exports"), secret: "TOP-SECRET-VALUE")

    let plist = fixture.defaults.persistentDomain(forName: fixture.name) ?? [:]
    let data = try PropertyListSerialization.data(
      fromPropertyList: plist, format: .xml, options: 0)
    let text = String(bytes: data, encoding: .utf8) ?? ""
    #expect(text.contains("Exports") && text.contains("SCWKEY"))
    #expect(!text.contains("TOP-SECRET-VALUE"))
    #expect(try fixture.secrets.read(saved.id.uuidString) == "TOP-SECRET-VALUE")
  }

  struct Row: Sendable, CustomTestStringConvertible {
    let label: String
    let connection: S3Connection
    let secret: String?
    let refusal: S3ConnectionStore.Refusal?
    var region = "fr-par"
    var testDescription: String { label }
  }

  static let rows: [Row] = [
    Row(
      label: "https endpoint", connection: draft("A"), secret: "s", refusal: nil),
    Row(
      label: "http on localhost (MinIO dev)",
      connection: draft("A", endpoint: "http://localhost:9000"), secret: "s", refusal: nil),
    Row(
      label: "http on 127.0.0.1", connection: draft("A", endpoint: "http://127.0.0.1:9000"),
      secret: "s", refusal: nil),
    Row(
      label: "http elsewhere refused", connection: draft("A", endpoint: "http://s3.example.com"),
      secret: "s", refusal: .insecureEndpoint("http://s3.example.com")),
    Row(
      label: "not a URL", connection: draft("A", endpoint: "s3.example.com"), secret: "s",
      refusal: .notAnEndpoint("s3.example.com")),
    Row(
      label: "empty region → us-east-1", connection: draft("A", region: "  "), secret: "s",
      refusal: nil, region: "us-east-1"),
    Row(
      label: "duplicate name refused (case-insensitive)", connection: draft(" taken "),
      secret: "s", refusal: .duplicateName("taken")),
    Row(label: "empty name refused", connection: draft("  "), secret: "s", refusal: .emptyName),
    Row(
      label: "endpoint with a path refused (it would be dropped)",
      connection: draft("A", endpoint: "https://minio.example.com/astro"), secret: "s",
      refusal: .endpointWithPath("https://minio.example.com/astro")),
    Row(
      label: "credentials in the URL refused (they would land in the defaults)",
      connection: draft("A", endpoint: "https://AK:SECRET@s3.example.com"), secret: "s",
      refusal: .notAnEndpoint("https://AK:SECRET@s3.example.com")),
    Row(
      label: "fragment refused", connection: draft("A", endpoint: "https://h.example#x"),
      secret: "s", refusal: .endpointWithPath("https://h.example#x")),
    Row(
      label: "trailing slash is no path", connection: draft("A", endpoint: "https://h.example/"),
      secret: "s", refusal: nil),
    Row(
      label: "no access key",
      connection: S3Connection(
        name: "A", endpoint: "https://h.example", region: "", pathStyle: false, accessKey: " "),
      secret: "s", refusal: .emptyAccessKey, region: "us-east-1"),
    Row(
      label: "new connection without its secret", connection: draft("A"), secret: "",
      refusal: .secretMissing),
  ]

  @Test("validation on save: endpoint, region, unique name, a secret", arguments: rows)
  func testValidation(row: Row) throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }
    _ = try fixture.store.save(Self.draft("Taken"), secret: "s")

    let result = Result { () throws(S3ConnectionStore.Refusal) in
      try fixture.store.save(row.connection, secret: row.secret)
    }

    switch result {
    case .success(let saved):
      #expect(row.refusal == nil)
      #expect(saved.region == row.region)
    case .failure(let refusal):
      #expect(refusal == row.refusal)
      #expect(fixture.store.connections.count == 1, "a refused connection stores nothing")
    }
  }

  @Test("a pasted secret loses its surrounding spaces and newline")
  func testSecretTrimmed() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }

    let saved = try fixture.store.save(Self.draft("A"), secret: "  abc123\n")

    #expect(try fixture.secrets.read(saved.id.uuidString) == "abc123")
  }

  @Test("newlines pasted around the fields are trimmed; a repeated id is read once")
  func testFieldsTrimmedAndDuplicatesDropped() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }
    var connection = Self.draft("A\n")
    connection.accessKey = "SCWKEY\n"

    let saved = try fixture.store.save(connection, secret: "s")

    #expect(saved.name == "A" && saved.accessKey == "SCWKEY")
    let text = try #require(fixture.defaults.string(forKey: S3ConnectionStore.key))
    let twice = "[" + text.dropFirst().dropLast() + "," + text.dropFirst().dropLast() + "]"
    fixture.defaults.set(twice, forKey: S3ConnectionStore.key)
    #expect(fixture.store.connections == [saved])
  }

  @Test("an unreadable stored list is never written over")
  func testUnreadableListKept() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }
    fixture.defaults.set("{not json", forKey: S3ConnectionStore.key)

    #expect(throws: S3ConnectionStore.Refusal.unreadableList) {
      try fixture.store.save(Self.draft("A"), secret: "s")
    }
    #expect(throws: S3ConnectionStore.Refusal.unreadableList) { try fixture.store.remove(UUID()) }
    #expect(fixture.defaults.string(forKey: S3ConnectionStore.key) == "{not json")
    #expect(fixture.store.connections.isEmpty)
  }

  @Test("a Keychain refusal is reported as such, never as « no secret »")
  func testKeychainRefusalSurfaced() throws {
    let fixture = try Fixture()
    defer { fixture.tearDown() }
    let saved = try fixture.store.save(Self.draft("A"), secret: "s")
    let denied = KeychainError(status: -25293)
    let locked = SecretStore(
      read: { _ in throw denied }, contains: { _ in throw denied }, write: { _, _ in throw denied },
      delete: { _ in throw denied })
    let store = S3ConnectionStore(defaults: fixture.defaults, secrets: locked)

    #expect(store.secretState(saved.id) == .unreadable(denied))
    #expect(throws: S3ConnectionStore.Refusal.keychain(denied)) {
      try store.credentials(for: saved.id)
    }
    #expect(throws: S3ConnectionStore.Refusal.keychain(denied)) {
      try store.save(saved, secret: nil)
    }
    #expect(throws: S3ConnectionStore.Refusal.keychain(denied)) {
      try store.save(saved, secret: "new")
    }
    #expect(throws: S3ConnectionStore.Refusal.keychain(denied)) { try store.remove(saved.id) }
    #expect(store.connections == [saved], "nothing changed")
  }

  @Test("every refusal reads as its own sentence in French and English")
  func testRefusalMessages() {
    let refusals: [S3ConnectionStore.Refusal] = [
      .emptyName, .duplicateName("A"), .notAnEndpoint("x"), .endpointWithPath("x"),
      .unreadableList, .insecureEndpoint("x"), .emptyAccessKey, .secretMissing,
      .keychain(KeychainError(status: -25293)),
    ]
    for language in ["en", "fr"] {
      let lines = refusals.map { refusal in
        var resource = UserFacingError.s3Connection(refusal).message
        resource.locale = Locale(identifier: language)
        return String(localized: resource)
      }
      #expect(Set(lines).count == refusals.count, "\(language): one sentence each")
      #expect(lines.allSatisfy { !$0.isEmpty })
    }
  }
}
